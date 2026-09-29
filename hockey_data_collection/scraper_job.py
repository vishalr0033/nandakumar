import os
import json
import time
import pandas as pd
from hockey_data_collection import config
from hockey_data_collection.scrapers.fih_scraper import FihScraper
from hockey_data_collection.parsers.match_parser import MatchParser
from tqdm import tqdm

def fetch_all():
    scraper = FihScraper()
    parser = MatchParser()
    
    # 1. Load existing repaired
    existing_df = pd.DataFrame()
    if os.path.exists("data/raw_matches_repaired.xlsx"):
        existing_df = pd.read_excel("data/raw_matches_repaired.xlsx")
        
    existing_urls = set(existing_df['source_match_url'].dropna().tolist()) if 'source_match_url' in existing_df.columns else set()
    print(f"Loaded {len(existing_urls)} existing match URLs.")

    # 2. Discover competitions
    comps = scraper.discover_competitions()
    print(f"Found {len(comps)} Senior Mens Outdoor competitions.")
    
    # 3. Extract matches
    all_match_urls = set()
    for comp in tqdm(comps, desc="Fetching matches list"):
        try:
            urls = scraper.get_matches_for_competition(comp)
            all_match_urls.update(urls)
        except Exception as e:
            print(f"Error extracting matches for {comp['name']}: {e}")
            
    print(f"Total unique match URLs found across competitions: {len(all_match_urls)}")
    
    # 4. Filter out existing
    new_urls = all_match_urls - existing_urls
    print(f"New match URLs to scrape: {len(new_urls)}")
    
    # 5. Scrape new matches concurrently
    new_records = []
    
    from concurrent.futures import ThreadPoolExecutor, as_completed
    
    def fetch_single_match(url):
        try:
            html = scraper.fetch_url(url)
            data = parser.parse_match(str(html))
            data['source_match_url'] = url
            data['source_name'] = "FIH TMS"
            data['scraped_at'] = pd.Timestamp.now().isoformat()
            
            if data['team_a_score'] is not None and data['team_b_score'] is not None:
                if data['team_a_score'] > data['team_b_score']:
                    data['winner'] = data['team_a']
                    data['loser'] = data['team_b']
                    data['result'] = 'A_WIN'
                elif data['team_b_score'] > data['team_a_score']:
                    data['winner'] = data['team_b']
                    data['loser'] = data['team_a']
                    data['result'] = 'B_WIN'
                else:
                    data['winner'] = 'DRAW'
                    data['loser'] = 'DRAW'
                    data['result'] = 'DRAW'
                    
                data['goal_difference'] = abs(data['team_a_score'] - data['team_b_score'])
                
            return data
        except Exception as e:
            print(f"Error scraping {url}: {e}")
            return None

    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(fetch_single_match, url): url for url in new_urls}
        for future in tqdm(as_completed(futures), total=len(new_urls), desc="Scraping new matches"):
            result = future.result()
            if result:
                new_records.append(result)
                
    # 6. Combine and save
    if new_records:
        new_df = pd.DataFrame(new_records)
        final_df = pd.concat([existing_df, new_df], ignore_index=True)
    else:
        final_df = existing_df
        
    final_df.to_excel(config.RAW_MATCHES_EXCEL, index=False)
    final_df.to_csv(config.RAW_MATCHES_CSV, index=False)
    print(f"Saved {len(final_df)} total records to {config.RAW_MATCHES_EXCEL}")

if __name__ == '__main__':
    fetch_all()
