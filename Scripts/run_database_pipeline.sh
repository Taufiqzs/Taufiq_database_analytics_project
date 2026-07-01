#!/usr/bin/env bash
# ------------------------------------------------------------------
# run_database_pipeline.sh
#
# End-to-end orchestration script for the NYC Taxi Analytics pipeline.
#
# This script:
#   1. Determines the project root directory.
#   2. Creates a timestamped log file under the `logs/` directory.
#   3. Starts the PostgreSQL container via Docker Compose.
#   4. Waits for the database to become ready (polling pg_isready).
#   5. Installs Python dependencies from requirements.txt.
#   6. Runs the main Python pipeline (Scripts/main.py).
#   7. Logs every step to both the console and the log file.
#
# Environment variables (with defaults):
#   POSTGRES_USER  – Database user name (default: training_user)
#   POSTGRES_DB    – Database name     (default: nyc_taxi_analytics)
# ------------------------------------------------------------------

set -euo pipefail

# --- Resolve project root and log file ----------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/pipeline_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

# --- Helper: log to both console and log file ---------------------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cd "$PROJECT_DIR"

# --- Step 1: Start the database container -------------------------------
log "Starting PostgreSQL with Docker Compose"
docker compose up -d db | tee -a "$LOG_FILE"

# --- Step 2: Wait for PostgreSQL to accept connections -------------------
log "Waiting for database readiness"
until docker compose exec -T db pg_isready -U "${POSTGRES_USER:-training_user}" -d "${POSTGRES_DB:-nyc_taxi_analytics}" >/dev/null 2>&1; do
  sleep 2
done

# --- Step 3: Install Python dependencies --------------------------------
log "Installing Python dependencies"
python3 -m pip install -r requirements.txt | tee -a "$LOG_FILE"

# --- Step 4: Execute the main Python ETL pipeline ------------------------
log "Running end-to-end database pipeline"
python3 Scripts/main.py 2>&1 | tee -a "$LOG_FILE"

# --- Done ---------------------------------------------------------------
log "Pipeline finished successfully"
