import os
from pathlib import Path

import requests


class ExtractData:
    """
    Menangani pengunduhan file data mentah (data perjalanan Parquet & lookup
    zona CSV) dari bucket publik S3 NYC TLC ke sistem file lokal.
    """

    # Derive the project root from the script's own location.
    BASE_DIR = Path(__file__).resolve().parents[1]
    RAW_DIR = BASE_DIR / "Data" / "Raw_data"

    def __init__(self, data_url: str | None = None, zone_lookup_url: str | None = None):
        """
        Menginisialisasi extractor.

        Jika tidak ada URL eksplisit yang diberikan, metode ini membaca dari
        variabel lingkungan ``DATA_URL`` dan ``ZONE_LOOKUP_URL``, menggunakan
        URL NYC TLC Januari 2026 taksi kuning & lookup zona sebagai default.

        Args:
            data_url:        URL file data perjalanan Parquet.
            zone_lookup_url: URL file lookup zona CSV.
        """
        self.data_url = data_url or os.getenv(
            "DATA_URL",
            "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2026-01.parquet",
        )
        self.zone_lookup_url = zone_lookup_url or os.getenv(
            "ZONE_LOOKUP_URL",
            "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv",
        )
        # Ensure the raw data directory exists.
        self.RAW_DIR.mkdir(parents=True, exist_ok=True)

    def download(self, url: str, filename: str) -> Path:
        """
        Mengunduh file dari ``url`` ke direktori data mentah lokal.

        Jika file sudah ada secara lokal, pengunduhan dilewati (tidak ada
        validasi checksum – hanya pemeriksaan keberadaan sederhana).

        Args:
            url:      URL remote untuk diunduh.
            filename: Nama file lokal untuk disimpan di ``RAW_DIR``.

        Mengembalikan:
            Path ke file yang diunduh (atau sudah ada).
        """
        destination = self.RAW_DIR / filename
        if destination.exists():
            print(f"[SKIP] {filename} already exists")
            return destination

        print(f"[DOWNLOAD] {url}")
        with requests.get(url, stream=True, timeout=120) as response:
            response.raise_for_status()
            total = int(response.headers.get("content-length", 0))
            downloaded = 0
            with destination.open("wb") as file:
                for chunk in response.iter_content(chunk_size=1024 * 1024):
                    if not chunk:
                        continue
                    file.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        print(f"\r  progress: {downloaded / total * 100:.1f}%", end="")
        print(f"\n[SAVED] {destination}")
        return destination

    def run(self) -> dict[str, Path]:
        """
        Mengorkestrasi ekstraksi: mengunduh file Parquet data perjalanan taksi
        dan file CSV lookup zona.

        Mengembalikan:
            Dictionary yang memetakan nama logis ("taxi_data", "zone_lookup") ke
            objek Path lokal yang sesuai.
        """
        taxi_file = self.download(self.data_url, self.data_url.split("/")[-1])
        zone_file = self.download(self.zone_lookup_url, self.zone_lookup_url.split("/")[-1])
        return {"taxi_data": taxi_file, "zone_lookup": zone_file}


if __name__ == "__main__":
    ExtractData().run()
