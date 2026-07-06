# ERD dan Desain Database

Database ini menggunakan model analitik berlapis:

- `bronze`: tabel staging mentah yang dimuat dari file sumber.
- `silver`: tabel analitik relasional yang dibersihkan dan divalidasi.
- `gold`: mart pelaporan teragregasi dan view kemudahan.
- `audit`: pelacakan eksekusi pipeline.

## ERD Utama

```mermaid
erDiagram
    audit_pipeline_run {
        BIGSERIAL run_id PK
        TEXT run_name
        TEXT status
        TIMESTAMPTZ started_at
        TIMESTAMPTZ finished_at
        TEXT message
    }

    audit_load_audit {
        BIGSERIAL audit_id PK
        BIGINT run_id FK
        TEXT layer_name
        TEXT object_name
        BIGINT row_count
        TEXT status
        TEXT message
        TIMESTAMPTZ logged_at
    }

    bronze_raw_taxi_zones {
        INTEGER location_id
        TEXT borough
        TEXT zone
        TEXT service_zone
        TEXT source_file
        TIMESTAMPTZ loaded_at
    }

    bronze_raw_taxi_trips {
        INTEGER vendor_id
        TIMESTAMP tpep_pickup_datetime
        TIMESTAMP tpep_dropoff_datetime
        NUMERIC passenger_count
        NUMERIC trip_distance
        INTEGER pu_location_id
        INTEGER do_location_id
        BIGINT payment_type
        NUMERIC fare_amount
        NUMERIC tip_amount
        NUMERIC total_amount
        TEXT source_file
        TIMESTAMPTZ loaded_at
    }

    silver_taxi_zones {
        INTEGER location_id PK
        TEXT borough
        TEXT zone
        TEXT service_zone
    }

    silver_taxi_trips_cleaned {
        BIGSERIAL trip_id PK
        INTEGER vendor_id
        TIMESTAMP pickup_datetime
        TIMESTAMP dropoff_datetime
        DATE pickup_date
        INTEGER pickup_hour
        TEXT pickup_day_name
        BOOLEAN is_weekend
        TEXT time_period
        NUMERIC trip_duration_minutes
        INTEGER passenger_count
        NUMERIC trip_distance
        INTEGER pickup_location_id FK
        INTEGER dropoff_location_id FK
        BIGINT payment_type
        TEXT payment_label
        NUMERIC fare_amount
        NUMERIC tip_amount
        NUMERIC total_amount
        TIMESTAMPTZ loaded_at
    }

    silver_data_quality_issues {
        BIGSERIAL issue_id PK
        TEXT error_type
        TEXT error_description
        INTEGER vendor_id
        TIMESTAMP pickup_datetime
        TIMESTAMP dropoff_datetime
        INTEGER pickup_location_id
        INTEGER dropoff_location_id
        NUMERIC passenger_count
        NUMERIC trip_distance
        NUMERIC fare_amount
        NUMERIC tip_amount
        NUMERIC total_amount
        TEXT source_file
        TIMESTAMPTZ logged_at
    }

    gold_daily_trip_summary {
        DATE pickup_date PK
        BIGINT total_trips
        NUMERIC total_revenue
        NUMERIC avg_revenue
        NUMERIC avg_fare
        NUMERIC avg_tip
        NUMERIC avg_distance
        NUMERIC avg_duration_minutes
    }

    gold_hourly_demand_summary {
        DATE pickup_date PK
        INTEGER pickup_hour PK
        TEXT time_period
        BIGINT total_trips
        NUMERIC total_revenue
        NUMERIC avg_duration_minutes
    }

    gold_zone_performance_summary {
        INTEGER location_id PK
        TEXT borough
        TEXT zone
        BIGINT total_pickup_trips
        NUMERIC total_revenue
        NUMERIC avg_fare
        NUMERIC avg_tip
        NUMERIC avg_distance
    }

    gold_payment_behavior_summary {
        BIGINT payment_type PK
        TEXT payment_label
        BIGINT total_trips
        NUMERIC total_revenue
        NUMERIC avg_revenue
        NUMERIC avg_tip
        NUMERIC avg_tip_ratio
    }

    gold_route_performance_summary {
        INTEGER pickup_location_id PK
        TEXT pickup_borough
        TEXT pickup_zone
        INTEGER dropoff_location_id PK
        TEXT dropoff_borough
        TEXT dropoff_zone
        BIGINT total_trips
        NUMERIC total_revenue
        NUMERIC avg_duration_minutes
        NUMERIC avg_distance
    }

    audit_pipeline_run ||--o{ audit_load_audit : mencatat

    bronze_raw_taxi_zones ||--|| silver_taxi_zones : membersihkan_ke
    bronze_raw_taxi_trips ||--o{ silver_taxi_trips_cleaned : memvalidasi_ke
    bronze_raw_taxi_trips ||--o{ silver_data_quality_issues : menolak_ke

    silver_taxi_zones ||--o{ silver_taxi_trips_cleaned : zona_pickup
    silver_taxi_zones ||--o{ silver_taxi_trips_cleaned : zona_dropoff

    silver_taxi_trips_cleaned ||--o{ gold_daily_trip_summary : agregasi_per_tanggal
    silver_taxi_trips_cleaned ||--o{ gold_hourly_demand_summary : agregasi_per_jam
    silver_taxi_zones ||--o{ gold_zone_performance_summary : agregasi_per_zona
    silver_taxi_trips_cleaned ||--o{ gold_zone_performance_summary : metrik_pickup
    silver_taxi_trips_cleaned ||--o{ gold_payment_behavior_summary : agregasi_per_pembayaran
    silver_taxi_trips_cleaned ||--o{ gold_route_performance_summary : agregasi_per_rute
```

## Catatan Relasi

Tabel fakta analitik utama adalah `silver.taxi_trips_cleaned`. Tabel ini menyimpan trip yang tervalidasi dan terhubung ke `silver.taxi_zones` dua kali:

- `pickup_location_id` merujuk ke `silver.taxi_zones.location_id`
- `dropoff_location_id` merujuk ke `silver.taxi_zones.location_id`

Tabel `gold` adalah mart pelaporan yang didenormalisasi dan dibangun dari layer silver. Tabel-tabel ini bukan tabel transaksional mentah; melainkan output teragregasi yang dirancang untuk dashboard, laporan, dan pertanyaan bisnis.

## View

Proyek ini juga membuat view kemudahan di skema `gold`:

- `gold.vw_trip_enriched`: trip bersih yang digabung dengan nama zona pickup dan dropoff.
- `gold.vw_daily_trip_summary`: view passthrough di atas `gold.daily_trip_summary`.
- `gold.vw_zone_performance`: performa zona dengan aktivitas pickup dan dropoff.

View ini berada di atas tabel silver dan gold, sehingga tidak disertakan dalam ERD utama sebagai entitas fisik.

## Granularitas (Grain)

| Objek | Granularitas |
| --- | --- |
| `bronze.raw_taxi_trips` | Satu baris trip sumber mentah |
| `bronze.raw_taxi_zones` | Satu baris lookup zona taksi mentah |
| `silver.taxi_zones` | Satu zona taksi bersih per `location_id` |
| `silver.taxi_trips_cleaned` | Satu trip taksi tervalidasi |
| `silver.data_quality_issues` | Satu record sumber yang ditolak atau tidak valid |
| `gold.daily_trip_summary` | Satu baris per tanggal pickup |
| `gold.hourly_demand_summary` | Satu baris per tanggal dan jam pickup |
| `gold.zone_performance_summary` | Satu baris per zona pickup |
| `gold.payment_behavior_summary` | Satu baris per tipe pembayaran |
| `gold.route_performance_summary` | Satu baris per pasangan zona pickup dan dropoff |
| `audit.pipeline_run` | Satu eksekusi pipeline |
| `audit.load_audit` | Satu langkah pipeline yang dicatat |