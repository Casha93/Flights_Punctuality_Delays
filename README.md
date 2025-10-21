# Flights_Punctuality_Delays


Цели проекта

Посчитать и визуализировать KPI пунктуальности рейсов: OTP15, средняя задержка прибытия, доля отмен.

Дать быстрый анализ по неделям, перевозчикам и маршрутам без долгих запросов.

Стек и данные

PostgreSQL (схема bi): dim_date, dim_airport, dim_carrier, fact_flights; матвью mv_week_route, mv_hour_patterns.

Power BI Desktop: связи, меры DAX, 3 графика (OTP15, Avg Arr Delay, Cancel Rate).

Быстрый старт

Импорт SQL: выполнить sql/data_clean_enrich.sql в БД trst_db.

Обновить витрины: REFRESH MATERIALIZED VIEW bi.mv_week_route; bi.mv_hour_patterns;.

Открыть pbix/Flights_Punctuality.pbix и указать подключение к trst_db.

Связи в Power BI

fact_flights[date_key] → dim_date[date_key] (активная, *:1).

origin_iata → dim_airport[airport_iata] (активная), dest_iata → dim_airport[airport_iata] (неактивная).

carrier_iata → dim_carrier[carrier_iata] (активная).

Ключевые меры DAX

Flights Count, Flights Count Clean, OTP15%, Avg Dep/Arr Delay (min), Cancel Rate %.


Как обновлять

Загрузить новые данные → выполнить sql/refresh_mv.sql → в Power BI нажать Обновить.


Что на дашборде

Тренд OTP15 по неделям, тренд средней задержки прибытия, тренд доли отмен; срезы: Перевозчик, Аэропорт, Период.

Имена файлов
Flights_Punctuality_Delays.pbix
flights_3m.csv
DDL_STAR.sql
date_dim.csv
data_clean_enrich.sql
carriers.csv
airports.csv

