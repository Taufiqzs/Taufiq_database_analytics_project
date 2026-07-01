from pathlib import Path

from database import DatabaseConnection
from extract_data import ExtractData
from load_to_postgres import BronzeLoader
from query_runner import QueryRunner


class SchemaManager:
    """
    Bertanggung jawab untuk menyiapkan skema database dengan mengeksekusi
    skrip SQL DDL yang disimpan di direktori ``db/init``.
    """

    def __init__(self, db: DatabaseConnection, sql_dir: Path):
        """
        Args:
            db:      Instance DatabaseConnection.
            sql_dir: Path ke direktori yang berisi skrip inisialisasi SQL.
        """
        self.db = db
        self.sql_dir = sql_dir

    def create_schema(self) -> None:
        """
        Menjalankan pembuatan skema inti (tabel, skema) dan skrip
        fungsi/prosedur.

        Menjalankan (berurutan):
          1. ``01_schema.sql``   – Pernyataan CREATE SCHEMA / TABLE.
          2. ``06_functions_procedures.sql`` – Fungsi logging audit.
        """
        self.db.execute_sql_file(self.sql_dir / "01_schema.sql")
        self.db.execute_sql_file(self.sql_dir / "06_functions_procedures.sql")

    def prepare_bronze(self) -> None:
        """
        Menjalankan skrip load layer bronze (``02_bronze_load.sql``) yang
        biasanya membuat tabel staging di dalam skema ``bronze``.
        """
        self.db.execute_sql_file(self.sql_dir / "02_bronze_load.sql")


class SilverTransformer:
    """
    Menjalankan transformasi SQL yang membersihkan dan memvalidasi data
    bronze dan menulis hasilnya ke skema ``silver``.
    """

    def __init__(self, db: DatabaseConnection, sql_dir: Path):
        """
        Args:
            db:      Instance DatabaseConnection.
            sql_dir: Path ke direktori yang berisi skrip inisialisasi SQL.
        """
        self.db = db
        self.sql_dir = sql_dir

    def run(self) -> None:
        """
        Menjalankan skrip transformasi layer silver
        (``03_silver_transform.sql``).
        """
        self.db.execute_sql_file(self.sql_dir / "03_silver_transform.sql")


class GoldMartBuilder:
    """
    Menjalankan pernyataan SQL yang membangun tabel layer Gold (mart)
    dan view tambahan di atasnya.
    """

    def __init__(self, db: DatabaseConnection, sql_dir: Path):
        """
        Args:
            db:      Instance DatabaseConnection.
            sql_dir: Path ke direktori yang berisi skrip inisialisasi SQL.
        """
        self.db = db
        self.sql_dir = sql_dir

    def run(self) -> None:
        """
        Menjalankan (berurutan):
          1. ``04_gold_mart.sql`` – Tabel agregat / ringkasan.
          2. ``05_views.sql``     – View untuk pelaporan.
        """
        self.db.execute_sql_file(self.sql_dir / "04_gold_mart.sql")
        self.db.execute_sql_file(self.sql_dir / "05_views.sql")


class LoadAuditRepository:
    """
    Menyediakan API sederhana untuk merekam langkah eksekusi pipeline di
    skema ``audit``, memungkinkan pelacakan run mana yang berhasil atau
    gagal dan berapa banyak baris yang dihasilkan setiap layer.
    """

    def __init__(self, db: DatabaseConnection):
        """
        Args:
            db: A DatabaseConnection instance.
        """
        self.db = db

    def start_run(self, run_name: str) -> int:
        """
        Menyisipkan record pipeline run baru dengan status 'STARTED' dan
        mengembalikan ID run yang dihasilkan.

        Args:
            run_name: Nama deskriptif untuk run (mis. 'nyc_taxi_database_pipeline').

        Mengembalikan:
            ``run_id`` integer dari run yang baru dibuat.
        """
        return int(
            self.db.scalar(
                "INSERT INTO audit.pipeline_run (run_name, status) "
                "VALUES (:run_name, 'STARTED') RETURNING run_id",
                run_name=run_name,
            )
        )

    def log_step(self, run_id: int, layer: str, object_name: str, row_count: int, status: str) -> None:
        """
        Menambahkan record langkah ke pipeline run saat ini melalui fungsi
        ``audit.log_pipeline_step``.

        Args:
            run_id:      ID run yang diperoleh dari ``start_run``.
            layer:       Nama layer data (mis. 'bronze', 'silver', 'gold').
            object_name: Tabel atau objek yang diproses.
            row_count:   Jumlah baris yang terpengaruh / dimuat.
            status:      Status langkah (mis. 'SUCCESS', 'FAILED').
        """
        self.db.execute(
            "SELECT audit.log_pipeline_step(:run_id, :layer, :object_name, :row_count, :status)",
            run_id=run_id,
            layer=layer,
            object_name=object_name,
            row_count=row_count,
            status=status,
        )

    def finish_run(self, run_id: int, status: str, message: str) -> None:
        """
        Menyelesaikan pipeline run dengan mengatur status akhir dan pesan.

        Args:
            run_id:  ID run.
            status:  Status akhir ('SUCCESS' atau 'FAILED').
            message: Ringkasan atau pesan error yang dapat dibaca manusia.
        """
        self.db.execute(
            "CALL audit.finish_pipeline_run(:run_id, :status, :message)",
            run_id=run_id,
            status=status,
            message=message,
        )


class TaxiAnalyticsPipeline:
    """
    Orkestrator tingkat atas yang menghubungkan seluruh pipeline ETL:

      1. Membuat skema database.
      2. Mengekstrak data mentah dari NYC TLC.
      3. Memuat data mentah ke layer bronze.
      4. Mentransformasi dari bronze → silver.
      5. Membuat mart (agregat) + view gold.
      6. Mengekspor hasil query sebagai file CSV.
      7. Mengaudit setiap langkah.
    """

    # Project root is two levels up from this script (scripts/ -> project root).
    BASE_DIR = Path(__file__).resolve().parents[1]

    def __init__(self):
        """
        Menginisialisasi pipeline, menyiapkan koneksi database dan
        menurunkan path standar yang digunakan di seluruh pipeline.
        """
        self.db = DatabaseConnection()
        self.sql_dir = self.BASE_DIR / "SQL" / "init"
        self.raw_dir = self.BASE_DIR / "Data" / "Raw_Data"
        self.output_dir = self.BASE_DIR / "Data"/ "Data_processed"
        self.audit = LoadAuditRepository(self.db)

    def _count(self, table_name: str) -> int:
        """
        Metode praktis yang mengembalikan jumlah total baris dalam sebuah tabel.

        Args:
            table_name: Nama tabel yang memenuhi syarat (mis. 'silver.taxi_trips_cleaned').

        Mengembalikan:
            Jumlah baris sebagai integer.
        """
        return int(self.db.scalar(f"SELECT COUNT(*) FROM {table_name}"))

    def run(self) -> None:
        """
        Menjalankan pipeline end-to-end secara lengkap.

        Langkah:
          1. Membuat skema, tabel, dan fungsi audit.
          2. Mendaftarkan pipeline run baru di log audit.
          3. Mengunduh file data mentah (ExtractData).
          4. Menyiapkan struktur tabel bronze dan memuat data mentah (BronzeLoader).
          5. Mencatat entri audit langkah bronze.
          6. Mentransformasi layer silver (SilverTransformer).
          7. Mencatat entri audit langkah silver.
          8. Membangun layer gold (GoldMartBuilder).
          9. Mencatat entri audit langkah gold.
          10. Mengekspor query bernama ke CSV (QueryRunner).
          11. Menandai pipeline run sebagai SUCCESS.

        Jika terjadi exception, run ditandai FAILED dan exception
        dilemparkan kembali.
        """
        # Step 1: Create database schema and audit infrastructure.
        SchemaManager(self.db, self.sql_dir).create_schema()
        run_id = self.audit.start_run("nyc_taxi_database_pipeline")

        try:
            # Step 2: Download raw data files.
            ExtractData().run()

            # Step 3: Prepare bronze staging and load data.
            schema = SchemaManager(self.db, self.sql_dir)
            schema.prepare_bronze()
            loaded_counts = BronzeLoader(self.db, self.raw_dir).run()
            for table_name, row_count in loaded_counts.items():
                self.audit.log_step(run_id, "bronze", table_name, row_count, "SUCCESS")

            # Step 4: Transform bronze data into cleaned silver tables.
            SilverTransformer(self.db, self.sql_dir).run()
            self.audit.log_step(
                run_id,
                "silver",
                "silver.taxi_trips_cleaned",
                self._count("silver.taxi_trips_cleaned"),
                "SUCCESS",
            )
            self.audit.log_step(
                run_id,
                "silver",
                "silver.data_quality_issues",
                self._count("silver.data_quality_issues"),
                "SUCCESS",
            )

            # Step 5: Build gold aggregated tables and views.
            GoldMartBuilder(self.db, self.sql_dir).run()
            for table_name in [
                "gold.daily_trip_summary",
                "gold.hourly_demand_summary",
                "gold.zone_performance_summary",
                "gold.payment_behavior_summary",
                "gold.route_performance_summary",
            ]:
                self.audit.log_step(run_id, "gold", table_name, self._count(table_name), "SUCCESS")

            # Step 6: Export results to CSV.
            QueryRunner(self.db, self.output_dir).export_named_queries()

            # Step 7: Mark the pipeline run as successful.
            self.audit.finish_run(run_id, "SUCCESS", "Pipeline completed")

        except Exception as exc:
            # If anything goes wrong, mark the run as FAILED and re-raise.
            self.audit.finish_run(run_id, "FAILED", str(exc))
            raise


if __name__ == "__main__":
    TaxiAnalyticsPipeline().run()
