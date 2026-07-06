#!/usr/bin/env bash
# ------------------------------------------------------------------
# run_database_pipeline.sh
#
# Skrip orkestrasi end-to-end untuk pipeline NYC Taxi Analytics.
#
# Skrip ini:
#   1. Menentukan direktori root proyek.
#   2. Membuat file log dengan timestamp di direktori `logs/`.
#   3. Memulai container PostgreSQL melalui Docker Compose.
#   4. Menunggu database siap (polling pg_isready).
#   5. Menginstal dependensi Python dari requirements.txt.
#   6. Menjalankan pipeline Python utama (Scripts/main.py).
#   7. Mencatat setiap langkah ke konsol dan file log.
#
# Variabel lingkungan (dengan nilai default):
#   POSTGRES_USER  – Nama pengguna database (default: training_user)
#   POSTGRES_DB    – Nama database     (default: nyc_taxi_analytics)
# ------------------------------------------------------------------

set -euo pipefail

# --- Menyelesaikan direktori root proyek dan file log -------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/pipeline_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

# --- Pembantu: catat ke konsol dan file log -----------------------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$PROJECT_DIR"

# --- Langkah 1: Mulai container database --------------------------------
log "Memulai PostgreSQL dengan Docker Compose"
docker compose up -d db | tee -a "$LOG_FILE"

# --- Langkah 2: Tunggu PostgreSQL siap menerima koneksi -----------------
log "Menunggu database siap"
until docker compose exec -T db pg_isready -U "${POSTGRES_USER:-training_user}" -d "${POSTGRES_DB:-nyc_taxi_analytics}" >/dev/null 2>&1; do
  sleep 2
done

# --- Langkah 3: Instal dependensi Python --------------------------------
log "Menginstal dependensi Python"
python3 -m pip install -r requirements.txt | tee -a "$LOG_FILE"

# --- Langkah 4: Jalankan pipeline ETL Python utama ----------------------
log "Menjalankan pipeline database end-to-end"
python3 Scripts/main.py 2>&1 | tee -a "$LOG_FILE"

# --- Selesai -----------------------------------------------------------
log "Pipeline selesai dengan sukses"