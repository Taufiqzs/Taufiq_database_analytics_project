import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine


@dataclass(frozen=True)
class DatabaseConfig:
    """
    Dataclass beku (immutable) yang menyimpan konfigurasi koneksi database.

    Atribut:
        host:     Hostname server PostgreSQL
        port:     Port server PostgreSQL
        database: Nama tujuan database
        user:     Nama pengguna database
        password: Kata sandi pengguna database
    """
    host: str
    port: int
    database: str
    user: str
    password: str

    @classmethod
    def from_env(cls) -> "DatabaseConfig":
        """
        Factory method yang membaca parameter koneksi PostgreSQL dari
        variabel lingkungan (atau menggunakan nilai default).

        Memuat file .env (jika ada) melalui `load_dotenv()` sehingga variabel
        lingkungan dapat diatur di luar environment global sistem.

        Mengembalikan:
            Instance DatabaseConfig yang terisi lengkap.
        """
        load_dotenv()
        return cls(
            host=os.getenv("POSTGRES_HOST", "localhost"),
            port=int(os.getenv("POSTGRES_PORT", "5437")),
            database=os.getenv("POSTGRES_DB", "nyc_taxi_analytics"),
            user=os.getenv("POSTGRES_USER", "training_user"),
            password=os.getenv("POSTGRES_PASSWORD", "Training_pass"),
        )

    @property
    def sqlalchemy_url(self) -> str:
        """
        Membangun URL koneksi yang kompatibel dengan SQLAlchemy dari field konfigurasi.

        Mengembalikan:
            String koneksi seperti
            "postgresql+psycop2://user:password@host:port/database".
        """
        return (
            f"postgresql+psycopg2://{self.user}:{self.password}"
            f"@{self.host}:{self.port}/{self.database}"
        )


class DatabaseConnection:
    """
    Pembungkus tipis di sekitar engine SQLAlchemy yang menyediakan metode praktis
    untuk mengeksekusi file SQL, query skalar, dan pernyataan SQL lainnya.
    """

    def __init__(self, config: DatabaseConfig | None = None):
        """
        Menginisialisasi pembungkus koneksi.

        Jika tidak ada `config` yang diberikan, konfigurasi default dibuat dari
        variabel lingkungan melalui `DatabaseConfig.from_env()`.

        Args:
            config: Instance DatabaseConfig opsional.
        """
        self.config = config or DatabaseConfig.from_env()
        self.engine: Engine = create_engine(self.config.sqlalchemy_url, future=True)

    def execute_sql_file(self, path: Path) -> None:
        """
        Membaca file SQL dari disk dan mengeksekusi isinya ke database
        dalam satu transaksi database mentah (raw).

        Koneksi raw digunakan agar file multi-pernyataan (misalnya
        mengandung beberapa perintah CREATE TABLE dengan titik koma)
        dapat dieksekusi sebagai satu kesatuan.

        Args:
            path: Path ke file .sql.
        """
        sql = path.read_text(encoding="utf-8")
        raw_connection = self.engine.raw_connection()
        try:
            with raw_connection.cursor() as cursor:
                cursor.execute(sql)
            raw_connection.commit()
        except Exception:
            raw_connection.rollback()
            raise
        finally:
            raw_connection.close()

    def execute_sql_files(self, paths: Iterable[Path]) -> None:
        """
        Menjalankan beberapa file SQL secara berurutan, mencetak pesan log
        sebelum setiap file.

        Args:
            paths: Iterable objek Path yang menunjuk ke file SQL.
        """
        for path in paths:
            print(f"[SQL] Running {path}")
            self.execute_sql_file(path)

    def scalar(self, sql: str, **params):
        """
        Menjalankan pernyataan SQL yang mengembalikan satu nilai skalar
        (misalnya COUNT atau klausa INSERT … RETURNING).

        Menggunakan context manager ``begin()`` SQLAlchemy sehingga transaksi
        di-commit secara otomatis jika berhasil.

        Args:
            sql:    Pernyataan SQL (dapat berisi placeholder bernama seperti
                    ``:param``).
            **params: Argumen kata kunci yang cocok dengan placeholder.

        Mengembalikan:
            Nilai skalar tunggal yang dikembalikan oleh query.
        """
        with self.engine.begin() as connection:
            return connection.execute(text(sql), params).scalar_one()

    def execute(self, sql: str, **params) -> None:
        """
        Menjalankan pernyataan SQL arbitrer (biasanya DML atau pernyataan CALL)
        dan melakukan commit transaksi secara otomatis.

        Args:
            sql:    Pernyataan SQL.
            **params: Parameter bernama untuk pernyataan tersebut.
        """
        with self.engine.begin() as connection:
            connection.execute(text(sql), params)
