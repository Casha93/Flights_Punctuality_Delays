-- 1 очистка и нормализация фактов

-- 1.1 Валидный флаг длительности
alter table bi.fact_flights add column if not exists duration_ok boolean;
update bi.fact_flights
set duration_ok = case
  when cancelled_flag = true then true
  when dep_ts_utc is not null and arr_ts_utc is not null and arr_ts_utc >= dep_ts_utc then true
  else false
end;

-- 1.2 Приведение кодов к верхнему регистру (на случай «грязных» источников)
update bi.fact_flights
set origin_iata = upper(origin_iata),
    dest_iata   = upper(dest_iata),
    carrier_iata= upper(carrier_iata);

-- 1.3 Нормализация NULL: пустые строки → NULL (если генератором создавались пустые)
update bi.fact_flights
set dep_ts_utc = nullif(dep_ts_utc::text,'')::timestamp,
    arr_ts_utc = nullif(arr_ts_utc::text,'')::timestamp,
    dep_delay_min = nullif(dep_delay_min::text,'')::int,
    arr_delay_min = nullif(arr_delay_min::text,'')::int;

-- 1.4 Опционально «починить» отрицательные длительности (если не нужны как аномалии)
-- закомментируй блок, если хочешь оставить для витрины качества
update bi.fact_flights
set dep_ts_utc = null, arr_ts_utc = null, dep_delay_min = null, arr_delay_min = null,
    duration_ok = false
where dep_ts_utc is not null and arr_ts_utc is not null and arr_ts_utc < dep_ts_utc;


-- 2 полезыне вычисляемые поля (обогащение)

-- 2.1 Час планового вылета/прилёта (UTC) для heatmap
alter table bi.fact_flights add column if not exists sched_dep_hour int;
alter table bi.fact_flights add column if not exists sched_arr_hour int;

update bi.fact_flights
set sched_dep_hour = extract(hour from sched_dep_ts_utc)::int,
    sched_arr_hour = extract(hour from sched_arr_ts_utc)::int;

-- 2.2 Длительности по расписанию и по факту (минуты)
alter table bi.fact_flights add column if not exists sched_duration_min int;
alter table bi.fact_flights add column if not exists actual_duration_min int;

update bi.fact_flights
set sched_duration_min = extract(epoch from (sched_arr_ts_utc - sched_dep_ts_utc))::int / 60,
    actual_duration_min = case
        when dep_ts_utc is not null and arr_ts_utc is not null
          then extract(epoch from (arr_ts_utc - dep_ts_utc))::int / 60
        else null
    end;

-- 2.3 Маркер «короткий/средний/дальний» перелёт по расписной длительности
alter table bi.fact_flights add column if not exists flight_band text;
update bi.fact_flights
set flight_band = case
  when sched_duration_min is null then null
  when sched_duration_min < 90 then 'short'
  when sched_duration_min < 180 then 'medium'
  else 'long'
end;


-- 3 Индексы для ускорения витрин

create index if not exists ix_f_duration_ok on bi.fact_flights(duration_ok);
create index if not exists ix_f_sched_dep_hour on bi.fact_flights(sched_dep_hour);
create index if not exists ix_f_sched_arr_hour on bi.fact_flights(sched_arr_hour);
create index if not exists ix_f_flight_band on bi.fact_flights(flight_band);

-- 4 Материализованные представления (агрегаты для Power BI)


-- 4.1 Недельные KPI по маршрутам и перевозчикам
drop materialized view if exists bi.mv_week_route cascade;
create materialized view bi.mv_week_route as
select
  d.year,
  d.week_iso,
  f.origin_iata,
  f.dest_iata,
  f.carrier_iata,
  count(*)                                  as flights_all,
  count(*) filter (where cancelled_flag=false and duration_ok=true) as flights_ok,
  100.0 * avg(case when cancelled_flag then 1 else 0 end)          as cancel_rate_pct,
  avg(dep_delay_min) filter (where cancelled_flag=false and duration_ok=true) as avg_dep_delay,
  avg(arr_delay_min) filter (where cancelled_flag=false and duration_ok=true) as avg_arr_delay,
  100.0 * avg(case when cancelled_flag=false and duration_ok=true and arr_delay_min <= 15 then 1 else 0 end) as otp15_pct
from bi.fact_flights f
join bi.dim_date d on d.date_key = f.date_key
group by 1,2,3,4,5;

create index if not exists ix_mv_week_route_keys on bi.mv_week_route(year, week_iso, origin_iata, dest_iata, carrier_iata);

-- 4.2 Часовые паттерны вылетов/задержек
drop materialized view if exists bi.mv_hour_patterns cascade;
create materialized view bi.mv_hour_patterns as
select
  d.year,
  d.week_iso,
  f.sched_dep_hour,
  f.origin_iata,
  f.carrier_iata,
  count(*) filter (where cancelled_flag=false and duration_ok=true) as flights_ok,
  avg(dep_delay_min) filter (where cancelled_flag=false and duration_ok=true) as avg_dep_delay
from bi.fact_flights f
join bi.dim_date d on d.date_key = f.date_key
group by 1,2,3,4,5;

create index if not exists ix_mv_hour_patterns_keys on bi.mv_hour_patterns(year, week_iso, sched_dep_hour, origin_iata, carrier_iata);


-- 5 контроль качества (повторные проверки)

-- Ссылочная целостность
select count(*) as missing_origin
from bi.fact_flights f left join bi.dim_airport a on f.origin_iata=a.airport_iata
where a.airport_iata is null;

select count(*) as missing_dest
from bi.fact_flights f left join bi.dim_airport a on f.dest_iata=a.airport_iata
where a.airport_iata is null;

select count(*) as missing_carrier
from bi.fact_flights f left join bi.dim_carrier c on f.carrier_iata=c.carrier_iata
where c.carrier_iata is null;

-- Логика времени
select count(*) as neg_duration
from bi.fact_flights
where dep_ts_utc is not null and arr_ts_utc is not null and arr_ts_utc < dep_ts_utc;

-- Доли отмен и OTP15 на «чистых» строках
select
  100.0 * avg(case when cancelled_flag then 1 else 0 end) as cancel_rate_pct,
  100.0 * avg(case when cancelled_flag=false and duration_ok=true and arr_delay_min <= 15 then 1 else 0 end) as otp15_pct
from bi.fact_flights;


-- 6 Обновленные матвью (при каждом перезаливе)

refresh materialized view concurrently bi.mv_week_route;
refresh materialized view concurrently bi.mv_hour_patterns;

