import argparse
import sys
import os

# Append current directory to path so we can run directly
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from hockey_data_collection.scrapers.fih_scraper import FihScraper
from hockey_data_collection.parsers.match_parser import MatchParser
from hockey_data_collection.processors.normalizer import Normalizer
from hockey_data_collection.validators.validator import Validator
from hockey_data_collection.exporters.excel_exporter import ExcelExporter

def discover_sources():
    print("Discovering sources...")
    scraper = FihScraper()
    comps = scraper.discover_competitions()
    with open("data_source_report.md", "w") as f:
        f.write("# Data Source Report\n\n")
        f.write(f"Source: {scraper.get_source_name()}\n")
        f.write(f"Competitions found: {len(comps)}\n")
        for c in comps:
            f.write(f"- {c['name']} ({c['url']})\n")
    print(f"Discovered {len(comps)} competitions and wrote to data_source_report.md")

def scrape_data(limit=None):
    print("Scraping data...")
    scraper = FihScraper()
    parser = MatchParser()
    normalizer = Normalizer()
    
    comps = scraper.discover_competitions()
    matches = []
    
    for comp in comps:
        if limit and len(matches) >= limit:
            break
        print(f"Fetching matches for {comp['name']}")
        match_urls = scraper.get_matches_for_competition(comp)
        
        for url in match_urls:
            if limit and len(matches) >= limit:
                break
            try:
                full_url = "https://fih.altiusrt.com" + url if url.startswith('/') else url
                html = scraper.fetch_match_html(full_url)
                if html:
                    match_data = parser.parse_match(html, full_url, comp['name'])
                    if match_data:
                        match_data = normalizer.process_match(match_data)
                        matches.append(match_data)
                        scraper.logger.info(f"Scraped {full_url}")
            except Exception as e:
                scraper.logger.error(f"Error processing {url}: {e}")
                
    # Validate and export
    validator = Validator()
    valid, invalid = validator.validate_data(matches)
    
    exporter = ExcelExporter()
    exporter.export(valid)
    
    print("========================================")
    print("HOCKEY HISTORICAL DATA COLLECTION")
    print("========================================")
    print(f"Collected: {len(matches)}")
    print(f"Unique: {len(valid)}")
    print(f"Invalid: {len(invalid)}")
    print("========================================")
    print("FILES CREATED:")
    print("raw_matches.xlsx")
    print("raw_matches.csv")
    print("validation_report.txt")
    print("========================================")

def main():
    parser = argparse.ArgumentParser(description="Hockey Data Collection Scraper")
    parser.add_argument("--discover-sources", action="store_true", help="Discover data sources")
    parser.add_argument("--limit", type=int, help="Limit number of matches to scrape")
    parser.add_argument("--scrape", action="store_true", help="Scrape matches")
    parser.add_argument("--validate", action="store_true", help="Validate existing data")
    parser.add_argument("--export", action="store_true", help="Export data")
    parser.add_argument("--all", action="store_true", help="Run the full pipeline")
    
    args = parser.parse_args()
    
    if args.discover_sources:
        discover_sources()
    elif args.limit:
        scrape_data(limit=args.limit)
    elif args.scrape or args.all:
        scrape_data()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
