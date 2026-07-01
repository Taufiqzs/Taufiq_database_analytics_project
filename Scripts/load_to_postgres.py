from io import StringIO
from pathlib import Path

import pandas as pd

from database import DatabaseConnection


class BronzeLoader:
    """
    Membaca file data mentah (perjalanan Parquet + zona CSV) dari sistem file,
    melakukan normalisasi kolom dasar (renaming, lowercasing, aligning),
    dan memuatnya secara massal ke tabel skema ``bronze``.

    ----------------------------------------------------------------
    CATATAN KINERJA — Mengapa kami menggunakan COPY instead of pandas to_sql:
    ----------------------------------------------------------------
    ``COPY ... FROM STDIN`` milik PostgreSQL 10–30× lebih cepat dari
    pandas ``to_sql`` karena:

      1. COPY melewati parser dan planner SQL sepenuhnya — data
         dialirkan langsung ke engine penyimpanan tabel sebagai byte mentah.
      2. Tidak ada overhead pembuatan SQL per-batch; seluruh
         dataset dikirim dalam satu pipa berkelanjutan.
      3. ``to_sql`` menghasilkan pernyataan ``INSERT INTO table VALUES (row1), ...``
         yang harus di-parse, di-plan, dan di-eksekusi oleh PostgreSQL
         untuk setiap batch — bahkan dengan ``method="multi"``.

    Pola yang digunakan di sini:
      - DataFrame → CSV di memori (StringIO) → ``copy_expert()``
      - Tanpa I/O disk, tanpa iterasi baris-per-baris Python, overhead minimal.
    ----------------------------------------------------------------
    """

    def __init__(self, db: DatabaseConnection, raw_dir: Path):
        """
        Args:
            db:      Instance DatabaseConnection yang digunakan untuk insert SQL.
            raw_dir: Path ke direktori yang berisi file data mentah.
        """
        self.db = db
        self.raw_dir = raw_dir

    def _find_file(self, pattern: str) -> Path:
        """
        Mengembalikan file pertama di ``raw_dir`` yang cocok dengan pola glob yang diberikan.

        Args:
            pattern: Pola glob (mis. ``"*.parquet"``).

        Mengembalikan:
            Satu objek Path.

        Memunculkan:
            FileNotFoundError jika tidak ada file yang cocok.
        """
        matches = sorted(self.raw_dir.glob(pattern))
        if not matches:
            raise FileNotFoundError(f"No file found for pattern {pattern} in {self.raw_dir}")
        return matches[0]

    def _align_columns(self, df: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
        """
        Memastikan DataFrame memiliki kolom yang tepat sesuai spesifikasi.

        Kolom yang hilang dari ``df`` ditambahkan (diisi dengan ``None``), dan
        DataFrame diurutkan ulang agar sesuai dengan daftar ``columns``.

        Args:
            df:      Input DataFrame.
            columns: Urutan kolom / superset yang diinginkan.

        Mengembalikan:
            DataFrame baru dengan kolom yang telah diselaraskan.
        """
        for column in columns:
            if column not in df.columns:
                df[column] = None
        return df[columns]

    def _copy_from_dataframe(self, df: pd.DataFrame, table: str, schema: str, columns: list[str]) -> int:
        """
        **Metode inti untuk kinerja** — menggunakan protokol ``COPY`` PostgreSQL
        sebagai pengganti pernyataan ``INSERT``.

        Cara kerjanya:
          1. DataFrame diserialisasi menjadi string CSV di memori.
             (``header=False`` karena COPY mengharapkan nilai mentah, bukan
             nama kolom.)
          2. Koneksi database mentah diperoleh dari SQLAlchemy.
          3. ``cur.copy_expert(sql, buffer)`` mengalirkan CSV langsung
             ke dalam tabel — tanpa parsing SQL, tanpa overhead batching.

        Args:
            df:      DataFrame yang akan dimuat.
            table:   Nama tabel tujuan (mis. ``"raw_taxi_trips"``).
            schema:  Nama skema tujuan (mis. ``"bronze"``).
            columns: Daftar kolom dalam urutan tepat yang diharapkan oleh tabel.

        Mengembalikan:
            Jumlah baris yang dimuat (harus sama dengan ``len(df)``).
        """
        # --- Step 1: Serialise DataFrame to an in-memory CSV buffer ---
        buffer = StringIO()
        df.to_csv(buffer, index=False, header=False)
        buffer.seek(0)

        # --- Step 2: Build the COPY SQL command ---
        # COPY ... FROM STDIN WITH (FORMAT CSV) tells PostgreSQL to
        # read raw CSV data from the client-side stream.
        column_list = ", ".join(columns)
        sql = f"""
            COPY {schema}.{table} ({column_list})
            FROM STDIN WITH (FORMAT CSV)
        """

        # --- Step 3: Execute COPY via a raw DBAPI connection ---
        # We use raw_connection() (not engine.begin()) because
        # copy_expert is a DBAPI-level operation, not a SQL statement.
        raw_conn = self.db.engine.raw_connection()
        try:
            with raw_conn.cursor() as cur:
                cur.copy_expert(sql, buffer)
            raw_conn.commit()
        except Exception:
            raw_conn.rollback()
            raise
        finally:
            raw_conn.close()

        return len(df)

    def load_taxi_trips(self) -> int:
        """
        Memuat file Parquet perjalanan taksi kuning ke ``bronze.raw_taxi_trips``.

        Metode ini:
          - Menemukan file Parquet.
          - Mengganti nama kolom uppercase menjadi lower-case/snake_case.
          - Menambahkan kolom ``source_file``.
          - Menyelaraskan kolom dengan definisi tabel tujuan.

          - Memuat massal ke PostgreSQL menggunakan ``COPY ... FROM STDIN``
            (≈10–30× lebih cepat dari pandas ``to_sql``).

        Mengembalikan:
            Jumlah baris yang dimuat.
        """
        path = self._find_file("yellow_tripdata_2026-01.parquet")
        df = pd.read_parquet(path)
        df = df.rename(
            columns={
                "VendorID": "vendor_id",
                "RatecodeID": "ratecode_id",
                "PULocationID": "pu_location_id",
                "DOLocationID": "do_location_id",
            }
        )
        df.columns = [column.lower() for column in df.columns]
        df["source_file"] = path.name
        df = self._align_columns(
            df,
            [
                "vendor_id",
                "tpep_pickup_datetime",
                "tpep_dropoff_datetime",
                "passenger_count",
                "trip_distance",
                "ratecode_id",
                "store_and_fwd_flag",
                "pu_location_id",
                "do_location_id",
                "payment_type",
                "fare_amount",
                "extra",
                "mta_tax",
                "tip_amount",
                "tolls_amount",
                "improvement_surcharge",
                "total_amount",
                "congestion_surcharge",
                "airport_fee",
                "cbd_congestion_fee",
                "source_file",
            ],
        )

        # --- Use COPY (fast path) instead of pandas to_sql ---
        return self._copy_from_dataframe(
            df,
            table="raw_taxi_trips",
            schema="bronze",
            columns=[
                "vendor_id",
                "tpep_pickup_datetime",
                "tpep_dropoff_datetime",
                "passenger_count",
                "trip_distance",
                "ratecode_id",
                "store_and_fwd_flag",
                "pu_location_id",
                "do_location_id",
                "payment_type",
                "fare_amount",
                "extra",
                "mta_tax",
                "tip_amount",
                "tolls_amount",
                "improvement_surcharge",
                "total_amount",
                "congestion_surcharge",
                "airport_fee",
                "cbd_congestion_fee",
                "source_file",
                        ],
        )

    def load_taxi_zones(self) -> int:
        """
        Memuat CSV lookup zona taksi ke ``bronze.raw_taxi_zones``.

        Langkah serupa dengan ``load_taxi_trips``: temukan, ganti nama, selaraskan, insert.

        Mengembalikan:
            Jumlah baris yang dimuat.
        """
        path = self._find_file("taxi_zone_lookup.csv")
        df = pd.read_csv(path)
        df = df.rename(
            columns={
                "LocationID": "location_id",
                "Borough": "borough",
                "Zone": "zone",
                "service_zone": "service_zone",
            }
        )
        df["source_file"] = path.name
        df = self._align_columns(
            df,
            ["location_id", "borough", "zone", "service_zone", "source_file"],
        )




        # --- Use COPY (fast path) instead of pandas to_sql ---
        return self._copy_from_dataframe(
            df,
            table="raw_taxi_zones",
            schema="bronze",
            columns=["location_id", "borough", "zone", "service_zone", "source_file"],
                )

    def run(self) -> dict[str, int]:
        """
        Menjalankan kedua operasi load dan mengembalikan dictionary dengan nama
        tabel sebagai kunci dan jumlah baris sebagai nilai.

        Mengembalikan:
            Dictionary seperti
            ``{"bronze.raw_taxi_zones": 265, "bronze.raw_taxi_trips": 12345}``.
        """
        return {
            "bronze.raw_taxi_zones": self.load_taxi_zones(),
            "bronze.raw_taxi_trips": self.load_taxi_trips(),
        }
