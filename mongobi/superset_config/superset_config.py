import os
from urllib.parse import quote_plus

# Persist rate-limit counters in Redis (prevents the in-memory warning)
RATELIMIT_STORAGE_URI = "redis://superset-redis:6379/1"

# Build Postgres DSN from env and URL-encode the password (handles @:/# etc.)
_pw = os.getenv("SUPERSET_DB_PASSWORD", "")

# Set up the metadata database connection for superset
SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://superset:{quote_plus(_pw)}@superset-db:5432/superset"
)

