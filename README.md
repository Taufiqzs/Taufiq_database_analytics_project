# New York Taxi Database Analytics

Capstone Project 2 ini membangun database analytics untuk data New York Taxi Januari 2026. Project ini melanjutkan hasil extract dari Capstone Project 1 ke PostgreSQL, lalu menerapkan medallion architecture: bronze, silver, dan gold.

## Business Objective

Database ini membantu perusahaan taxi menjawab pertanyaan bisnis terkait:

- demand perjalanan
- revenue dan fare behavior
- payment behavior
- area pickup dan dropoff
- performa berdasarkan waktu
- kualitas data

## Tech Stack

- PostgreSQL 16
- Docker Compose
- Python sebagai orchestration layer
- SQL untuk DDL, transformasi, data mart, view, CTE, dan window function

## Folder Structure

```text
taufiq_database_analytics/
├── Data/
│   ├── Raw_Data/
│   └── Data_processed/
├── Documentation/
│   ├── database_analytics_erd.drawio
│   ├── database_analytics_erd.png
│   ├── erd.md
│   └── insight_report.md
├── SQL/
│   ├── init/
│   │   ├── 01_schema.sql
│   │   ├── 02_bronze_load.sql
│   │   ├── 03_silver_transform.sql
│   │   ├── 04_gold_mart.sql
│   │   ├── 05_views.sql
│   │   └── 06_functions_procedures.sql
│   └── queries/
│       ├── 01_business_questions.sql
│       ├── 02_window_analysis.sql
│       └── 03_transaction_demo.sql
├── Scripts/
│   ├── database.py
│   ├── extract_data.py
│   ├── load_to_postgres.py
│   ├── main.py
│   ├── query_runner.py
│   └── run_database_pipeline.sh
├── docker-compose.yaml
├── requirements.txt
└── README.md
``\

## Data Source

File raw data akan diunduh secara otomatis oleh `Scripts/extract_data.py`:

- `yellow_tripdata_2026-01.parquet`
- `taxi_zone_lookup.csv`

File raw data tidak dimasukkan ke Git agar repository tidak menyimpan file berukuran besar.

## How To Run

Jalankan database PostgreSQL dengan Docker Compose:

```bash
docker compose up -d db
```

Buat dan aktifkan virtual environment jika diperlukan:

```bash
python3 -m venv .venv_wsl
source .venv_wsl/bin/activate
```

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

Jalankan full pipeline:

```bash
./Scripts/run_database_pipeline.sh
```

Script automation akan menjalankan proses berikut:

1. menjalankan PostgreSQL dengan Docker Compose
2. membuat schema, tabel, constraint, function, dan procedure
3. mengunduh raw taxi data dan zone lookup jika file belum tersedia
4. melakukan truncate dan load data ke tabel bronze
5. mentransformasi data bronze ke silver menggunakan SQL
6. membangun gold marts dan views menggunakan SQL
7. mengekspor beberapa output analisis ke `Data/Data_processed/`
8. menyimpan log pipeline ke folder `logs/`

## Manual Commands

Menjalankan database:

```bash
docker compose up -d db
```

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

Menjalankan pipeline Python:

```bash
python Scripts/main.py
```

## Medallion Architecture

### Bronze

Bronze menyimpan data raw atau staging yang dimuat langsung dari file sumber:

- `bronze.raw_taxi_trips`
- `bronze.raw_taxi_zones`

Struktur tabel di layer bronze dibuat mendekati struktur file sumber dan hanya memiliki sedikit business logic. Layer ini berfungsi sebagai tempat awal sebelum data dibersihkan.

### Silver

Silver menyimpan data yang sudah dibersihkan, distandarisasi, dan divalidasi:

- `silver.taxi_zones`
- `silver.taxi_trips_cleaned`
- `silver.data_quality_issues`

Transformasi utama pada layer silver meliputi:

- standardisasi datetime
- pembuatan pickup date, pickup hour, day name, weekend flag, dan time period
- perhitungan durasi perjalanan dalam menit
- mapping payment type menjadi label yang lebih mudah dibaca
- validasi foreign key ke tabel taxi zones
- pencatatan data yang tidak lolos validasi ke `silver.data_quality_issues`

### Gold

Gold menyimpan data mart dan view yang siap digunakan untuk reporting dan analisis:

- `gold.daily_trip_summary`
- `gold.hourly_demand_summary`
- `gold.zone_performance_summary`
- `gold.payment_behavior_summary`
- `gold.route_performance_summary`
- `gold.vw_trip_enriched`
- `gold.vw_daily_trip_summary`
- `gold.vw_zone_performance`

Layer gold dibuat dari data silver yang sudah valid, sehingga query analisis dapat berjalan lebih sederhana dan konsisten.

## Database Design

Project ini menggunakan empat schema utama:

- `bronze`: layer raw/staging
- `silver`: layer data bersih dan tervalidasi
- `gold`: layer reporting dan analytics
- `audit`: layer pencatatan pipeline run dan load process

Constraint yang digunakan meliputi:

- primary key pada tabel silver dan gold
- foreign key dari tabel trip ke tabel taxi zones
- not null constraint untuk kolom wajib
- check constraint untuk nilai amount non-negatif dan hour yang valid
- unique constraint untuk mencegah duplicate trip loading

Penjelasan hubungan antar tabel dapat dilihat di `Documentation/erd.md`. Versi visual yang bisa dibuka di draw.io tersedia di `Documentation/database_analytics_erd.drawio`.

## Business Questions

File SQL di folder `SQL/queries` digunakan untuk menjawab pertanyaan bisnis seperti:

- total valid trips
- total revenue, average revenue, average fare, dan average tip
- peak trip date dan peak trip hour
- perbandingan weekday versus weekend trips
- payment type yang paling sering digunakan
- pickup borough dan pickup zone dengan demand tertinggi
- pickup zone dengan revenue tertinggi
- rute pickup-dropoff yang paling sering muncul
- performa berdasarkan time period
- jumlah data quality issue
- pola trip count yang tidak biasa
- top zones by revenue
- high pickup zones dengan average tip rendah
- daily revenue dibandingkan rata-rata
- above-average duration trips by zone
- low-contribution pickup boroughs
- zone ranking
- borough-level zone ranking
- running total revenue
- 7-day moving average trip count
- perbandingan menggunakan `LAG` terhadap hari sebelumnya
- demonstrasi transaksi dan rollback (BEGIN/ROLLBACK)

File query utama:

- `SQL/queries/01_business_questions.sql` — 11 query bisnis fundamental
- `SQL/queries/02_window_analysis.sql` — 10 query window function lanjutan
- `SQL/queries/03_transaction_demo.sql` — Demonstrasi transaksi database

## Assumptions and Notes

- File trip utama adalah official January 2026 yellow taxi Parquet file.
- Raw data dapat mengandung record invalid atau suspicious; record tersebut disimpan di `silver.data_quality_issues`.
- Python digunakan untuk orchestration pipeline, sedangkan SQL berisi desain database, transformasi, data mart, view, dan logic analitik utama.
- Pipeline melakukan truncate pada bronze dan membangun ulang silver/gold layer agar dapat dijalankan ulang tanpa hasil duplikat.
- Nilai insight akhir sebaiknya dihasilkan setelah pipeline dijalankan, karena nilainya bergantung pada raw dataset yang berhasil diunduh.
- Seluruh komentar pada file Python, SQL, dan shell script telah diterjemahkan ke Bahasa Indonesia.