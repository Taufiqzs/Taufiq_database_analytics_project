# Laporan Insight

Laporan ini dihasilkan dari SQL mart dan query pertanyaan bisnis setelah menjalankan pipeline.

## Ringkasan Eksekutif

Proyek ini membangun database analitik PostgreSQL untuk New York Taxi Januari 2026. Database ini mendukung analisis demand, analisis revenue, analisis perilaku pembayaran, performa zona, performa rute, analisis tren berbasis waktu, dan pemantauan kualitas data.

## Sumber Analisis

Gunakan file SQL berikut untuk menghasilkan insight:

- `SQL/queries/01_business_questions.sql`
- `SQL/queries/02_window_analysis.sql`

Pipeline juga mengekspor file CSV terpilih ke `Data/Data_processed/`:

- `daily_summary.csv`
- `top_pickup_zones.csv`
- `payment_behavior.csv`
- `data_quality_issues.csv`

## Area Insight Utama

### Demand Perjalanan

Gunakan `gold.daily_trip_summary` dan `gold.hourly_demand_summary` untuk mengidentifikasi tanggal dan jam tersibuk di Januari 2026.

### Revenue

Gunakan `gold.daily_trip_summary`, `gold.zone_performance_summary`, dan `gold.route_performance_summary` untuk membandingkan total revenue berdasarkan hari, zona pickup, dan rute.

### Perilaku Pembayaran

Gunakan `gold.payment_behavior_summary` untuk membandingkan frekuensi tipe pembayaran, total revenue, rata-rata revenue, rata-rata tip, dan rasio tip.

### Performa Zona dan Rute

Gunakan `gold.zone_performance_summary`, `gold.vw_zone_performance`, dan `gold.route_performance_summary` untuk menemukan zona dengan demand tinggi, zona dengan revenue tinggi, dan rute yang sering digunakan.

### Kualitas Data

Gunakan `silver.data_quality_issues` untuk memantau durasi tidak valid, jumlah penumpang tidak valid, jarak tidak valid, jumlah negatif, lokasi tidak dikenal, dan record di luar Januari 2026.

### Analisis Window Function

Gunakan `SQL/queries/02_window_analysis.sql` untuk:

- peringkat zona pickup berdasarkan revenue
- peringkat zona pickup per borough
- total revenue berjalan berdasarkan tanggal
- rata-rata bergerak 7 hari jumlah trip
- perbandingan revenue hari sebelumnya dengan `LAG`
- deteksi zona pickup tinggi dan tip rendah

## Asumsi Teknis

- Data trip mentah berasal dari file Parquet taksi kuning Januari 2026.
- Data lookup zona berasal dari CSV lookup zona taksi resmi.
- Tabel bronze adalah tabel staging dan dipotong (truncate) sebelum dimuat ulang.
- Layer silver dan gold dibangun ulang dari SQL sehingga proses ulang bersifat idempoten.
- Hasil numerik akhir sebaiknya diisi setelah menjalankan pipeline di mesin lokal.
