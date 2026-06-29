#test
import os
import requests
from pathlib import Path



class Extract_data:

    #Folder  raw data files ke direktori data/raw_data_pl 
    # perlu di kasi ./ dibelakang data agar data yang download masuk ke dalam folder taufiq_nyt_pipeline\data\raw_data_pl bukan buat baru
    BASE_DIR = Path(__file__).resolve().parents[1]
    RAW_DIR = BASE_DIR / Path("./Data/Raw_data")
  
 
 
    def __init__(self, data_url: str = None, ZONE_LOOKUP_URL: str=None):
        # environment variable DATA_URL (Docker)
        # URL default hardcode

        self.data_url = data_url or os.getenv(
            "DATA_URL",
            "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2026-01.parquet"
        )
        self.ZONE_LOOKUP_URL = ZONE_LOOKUP_URL or os.getenv(
            "ZONE_LOOKUP_URL",
            "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
        )
        # membuat folder data/raw/ jika belum ada
        self.RAW_DIR.mkdir(parents=True, exist_ok=True)
 
 
    def download(self, url: str, filename: str) -> Path:
        """Mengunduh satu file dari URL dan menyimpannya ke data/raw/"""
        # bisa menggunakan os.path.join("data/raw_data_pl", "yellow_tripdata_2026-01.parquet") tapi cara yang baru pakai Path()

        # Buat path tujuan lengkap, misal: data/raw/taxi_zone_lookup.csv
        dest = self.RAW_DIR / filename
 
        # Jika file sudah ada, lewati proses download untuk menghemat waktu
        # fungsi exists sudah ada di library python pathlib.path
        if dest.exists():
            print(f"[SKIP] {filename} sudah ada, melewati proses download.")
            return dest
 
        print(f"[DOWNLOAD] {filename} dari:\n  {url}")
 
        # stream=True artinya download dilakukan per bagian (chunk)
        # bukan sekaligus, agar file 61MB tidak dimuat penuh ke memori
        response = requests.get(url, stream=True)
 
        # Tampilkan error jika request gagal (misal: 404, 500)
        response.raise_for_status()
 
        # Ambil ukuran total file dari header respons (untuk menampilkan %)
        total = int(response.headers.get("content-length", 0))
        downloaded = 0
 
        # untuk mengetahui jalannya download, download di bagi per 8 KiloByte agar lebih mudah dan cepat download
        with open(dest, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):  # per 8KB
                f.write(chunk)
                downloaded += len(chunk)
 
                # Tampilkan persentase progres download
                if total:
                    pct = downloaded / total * 100
                    print(f"\r  Progres: {pct:.1f}%", end="", flush=True)
 
        print(f"\n[SELESAI] Disimpan ke {dest}")
        return dest
 
 
    def extract_taxi_data(self) -> Path:
        """Mengunduh file parquet data taxi utama"""
 
        # Ambil nama file dari URL, "yellow_tripdata_2026-01.parquet",
        #'/' buat motong url jadi setiap ketemu karakter '/' mesin mengambil string sebelum tanda '/', [-1] ambil elemen terakhir
    
        filename = self.data_url.split("/")[-1]
        return self.download(self.data_url, filename)
 
 
    def extract_zone_lookup(self) -> Path:
        """Mengunduh file CSV zona taxi"""
        filename = self.ZONE_LOOKUP_URL.split("/")[-1]
        return self.download(self.ZONE_LOOKUP_URL, filename)
 
 
    def run(self) -> dict:
        """
        Method utama — menjalankan seluruh tahap ekstraksi.
        Dipanggil oleh run_pipeline.sh
        Mengembalikan path file yang diunduh 
        """
        print("=" * 10)
        print("EKSTRAKSI")
        print("=" * 10)
 
        # Unduh kedua file
        taxi_path = self.extract_taxi_data()
        zone_path = self.extract_zone_lookup()
 
        print("\n[EKSTRAKSI] Berhasil diselesaikan!")
        print(f"  Data taxi   : {taxi_path}")
        print(f"  Zone lookup : {zone_path}")
 
        # mengembalikan path supaya transform.py tahu lokasi file
        return {
            "taxi_data": taxi_path,
            "zone_lookup": zone_path
        }
 
 
# ketika eksekusi: python3 scripts/extract.py Tidak akan berjalan jika extract.py diimpor oleh script lain
if __name__ == "__main__":
    extractor = Extract_data()   # buat instance dari class Extract_data
    extractor.run()