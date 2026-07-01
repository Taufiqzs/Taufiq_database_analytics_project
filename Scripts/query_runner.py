from pathlib import Path

import pandas as pd
from sqlalchemy import text

from database import DatabaseConnection


class QueryRunner:
    """
    Menjalankan serangkaian query SQL analitis yang telah ditentukan terhadap database
    dan mengekspor hasilnya sebagai file CSV ke direktori output yang ditentukan.
    """

    def __init__(self, db: DatabaseConnection, output_dir: Path):
        """
        Args:
            db:         Instance DatabaseConnection.
            output_dir: Path ke direktori tempat ekspor CSV akan disimpan.
        """
        self.db = db
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def export_named_queries(self) -> None:
        """
        Menjalankan empat query analitis standar dan menulis setiap hasil ke
        file CSV.

        Query yang dijalankan:
          - ``daily_summary``        -> ``gold.daily_trip_summary``
          - ``top_pickup_zones``     -> 20 zona teratas berdasarkan revenue
          - ``payment_behavior``     -> ``gold.payment_behavior_summary``
          - ``data_quality_issues``  -> tipe error yang diagregasi

        Setiap file dinamai sesuai kunci query (mis. ``daily_summary.csv``).
        """
        queries = {
            "daily_summary": "SELECT * FROM gold.daily_trip_summary ORDER BY pickup_date",
            "top_pickup_zones": (
                "SELECT borough, zone, total_pickup_trips, total_revenue "
                "FROM gold.zone_performance_summary "
                "ORDER BY total_revenue DESC NULLS LAST LIMIT 20"
            ),
            "payment_behavior": (
                "SELECT * FROM gold.payment_behavior_summary ORDER BY total_trips DESC"
            ),
            "data_quality_issues": (
                "SELECT error_type, COUNT(*) AS issue_count "
                "FROM silver.data_quality_issues GROUP BY error_type ORDER BY issue_count DESC"
            ),
        }

        with self.db.engine.begin() as connection:
            for name, query in queries.items():
                df = pd.read_sql_query(text(query), connection)
                output_path = self.output_dir / f"{name}.csv"
                df.to_csv(output_path, index=False)
                print(f"[EXPORT] {output_path} ({len(df)} rows)")
