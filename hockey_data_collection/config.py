import os
from pathlib import Path

# Paths
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
LOGS_DIR = BASE_DIR / "logs"

# Ensure directories exist
DATA_DIR.mkdir(exist_ok=True)
LOGS_DIR.mkdir(exist_ok=True)

# File paths
RAW_MATCHES_CSV = DATA_DIR / "hockey_matches_final.csv"
RAW_MATCHES_EXCEL = DATA_DIR / "hockey_matches_final.xlsx"
TEAM_MAPPING_CSV = DATA_DIR / "team_name_mapping.csv"
DUPLICATE_REPORT_CSV = DATA_DIR / "duplicate_report.csv"
DATA_CONFLICTS_CSV = DATA_DIR / "data_conflicts.csv"
SCRAPING_LOG_CSV = DATA_DIR / "scraping_log.csv"
VALIDATION_REPORT_TXT = DATA_DIR / "validation_report.txt"
CHECKPOINT_FILE = BASE_DIR / "checkpoint.json"

# Scraping settings
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
MIN_DELAY = 1.0
MAX_DELAY = 3.0

# Base URLs
FIH_BASE_URL = "https://fih.altiusrt.com"
TMS_COMPETITIONS_URL = "https://tms.fih.ch/competitions"
