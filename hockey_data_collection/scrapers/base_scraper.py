import json
import logging
import time
import random
from pathlib import Path
from urllib.parse import urlparse
import requests
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from hockey_data_collection import config

class ScrapingError(Exception):
    pass

class BaseScraper:
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": config.USER_AGENT})
        self.checkpoint_data = self._load_checkpoint()
        self.setup_logging()

    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(config.LOGS_DIR / "scraping.log"),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def _load_checkpoint(self):
        if config.CHECKPOINT_FILE.exists():
            with open(config.CHECKPOINT_FILE, "r") as f:
                return json.load(f)
        return {"last_processed_url": None, "last_processed_page": 0, "records_collected": 0, "timestamp": time.time()}

    def save_checkpoint(self, records_collected, url=None, page=0):
        self.checkpoint_data = {
            "last_processed_url": url,
            "last_processed_page": page,
            "records_collected": records_collected,
            "timestamp": time.time()
        }
        with open(config.CHECKPOINT_FILE, "w") as f:
            json.dump(self.checkpoint_data, f, indent=4)

    def log_scrape(self, source_name, url, http_status, status, records_found=0, records_added=0, duplicates=0, error=""):
        log_entry = f"{time.time()},{source_name},{url},{http_status},{status},{records_found},{records_added},{duplicates},{error}\n"
        is_new = not config.SCRAPING_LOG_CSV.exists()
        with open(config.SCRAPING_LOG_CSV, "a", encoding="utf-8") as f:
            if is_new:
                f.write("timestamp,source_name,url,http_status,status,records_found,records_added,duplicates_found,error_message\n")
            f.write(log_entry)

    @retry(stop=stop_after_attempt(5), wait=wait_exponential(multiplier=1, min=2, max=10), 
           retry=retry_if_exception_type((requests.exceptions.ConnectionError, requests.exceptions.Timeout, ScrapingError)))
    def fetch_url(self, url):
        time.sleep(random.uniform(0.01, 0.1))
        try:
            self.logger.info(f"Fetching {url}")
            response = self.session.get(url, timeout=15)
            
            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", 10))
                self.logger.warning(f"Rate limited. Waiting {retry_after} seconds.")
                time.sleep(retry_after)
                raise ScrapingError("Rate limited")
                
            if response.status_code == 404:
                raise ValueError("404 Not Found")
                
            response.raise_for_status()
            return BeautifulSoup(response.text, 'html.parser')
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            self.logger.error(f"Error fetching {url}: {e}")
            raise
        except ValueError:
            raise

    def get_source_name(self):
        return "BaseSource"
