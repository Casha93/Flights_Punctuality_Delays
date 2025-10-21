-- Создание схем, таблиц и индексов

create schema if not exists bi;

create table if not exists bi.dim_airport (
  airport_iata text primary key,
  airport_icao text not null,
  name text not null,
  city text not null,
  country text not null,
  tz text not null,
  latitude double precision not null,
  longitude double precision not null
);

create table if not exists bi.dim_carrier (
  carrier_iata text primary key,
  carrier_icao text not null,
  carrier_name text not null
);

create table if not exists bi.dim_date (
  date_key integer primary key,
  date date not null,
  day_of_week smallint not null,
  day_name_ru text not null,
  week_iso smallint not null,
  month smallint not null,
  month_name_ru text not null,
  quarter smallint not null,
  year integer not null,
  is_weekend boolean not null,
  is_holiday_ru boolean not null
);

create table if not exists bi.fact_flights (
  flight_id bigint primary key,
  date_key integer not null references bi.dim_date(date_key),
  sched_dep_ts_utc timestamp not null,
  sched_arr_ts_utc timestamp not null,
  dep_ts_utc timestamp null,
  arr_ts_utc timestamp null,
  origin_iata text not null references bi.dim_airport(airport_iata),
  dest_iata text not null references bi.dim_airport(airport_iata),
  carrier_iata text not null references bi.dim_carrier(carrier_iata),
  dep_delay_min integer null,
  arr_delay_min integer null,
  cancelled_flag boolean not null
);

create index if not exists ix_f_flights_date on bi.fact_flights(date_key);
create index if not exists ix_f_flights_origin on bi.fact_flights(origin_iata);
create index if not exists ix_f_flights_dest on bi.fact_flights(dest_iata);
create index if not exists ix_f_flights_carrier on bi.fact_flights(carrier_iata);

-- загрузка CSV файлов с данными

copy bi.dim_airport  from 'D:\BI\airports.csv'  csv header encoding 'UTF8';
copy bi.dim_carrier  from 'D:\BI\carriers.csv'  csv header encoding 'UTF8';
copy bi.dim_date     from 'D:\BI\date_dim.csv'  csv header encoding 'UTF8';
copy bi.fact_flights from 'D:\BI\flights_3m.csv' csv header encoding 'UTF8' null '';

-- быстрая проверка качества данных

-- 1) ссылочная целостность
select count(*) as missing_origin from bi.fact_flights f left join bi.dim_airport a on f.origin_iata=a.airport_iata where a.airport_iata is null;
select count(*) as missing_dest   from bi.fact_flights f left join bi.dim_airport a on f.dest_iata=a.airport_iata   where a.airport_iata is null;
select count(*) as missing_carrier from bi.fact_flights f left join bi.dim_carrier c on f.carrier_iata=c.carrier_iata where c.carrier_iata is null;

-- 2) логика времени
select count(*) as neg_duration from bi.fact_flights where dep_ts_utc is not null and arr_ts_utc is not null and arr_ts_utc < dep_ts_utc;

-- 3) диапазоны задержек
select min(dep_delay_min), max(dep_delay_min), min(arr_delay_min), max(arr_delay_min) from bi.fact_flights where cancelled_flag=false;

-- 4) отмены в разумном диапазоне
select 100.0*avg(case when cancelled_flag then 1 else 0 end) as cancel_rate_pct from bi.fact_flights;
