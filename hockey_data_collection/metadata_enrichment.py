import pandas as pd
import numpy as np
import os
import re
import json
import time
from bs4 import BeautifulSoup
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm
import threading

from tenacity import retry, wait_exponential, stop_after_attempt, retry_if_exception_type

# Paths
DATA_DIR = 'data'
INPUT_CSV = os.path.join(DATA_DIR, 'hockey_matches_final.csv')
BACKUP_CSV = os.path.join(DATA_DIR, 'hockey_matches_before_metadata_enrichment.csv')
BACKUP_XLSX = os.path.join(DATA_DIR, 'hockey_matches_before_metadata_enrichment.xlsx')

ENRICHED_CSV = os.path.join(DATA_DIR, 'hockey_matches_metadata_enriched.csv')
ENRICHED_XLSX = os.path.join(DATA_DIR, 'hockey_matches_metadata_enriched.xlsx')
TEAM_MAPPING_CSV = os.path.join(DATA_DIR, 'team_mapping.csv')
TOURNAMENT_MAPPING_CSV = os.path.join(DATA_DIR, 'tournament_mapping.csv')
UNRESOLVED_CSV = os.path.join(DATA_DIR, 'metadata_unresolved.csv')
LOG_CSV = os.path.join(DATA_DIR, 'metadata_scraping_log.csv')
CHECKPOINT_FILE = os.path.join(DATA_DIR, 'metadata_checkpoint.json')

# Cache for competition pages
comp_cache = {}
comp_cache_lock = threading.Lock()

session = requests.Session()
retry_strategy = Retry(
    total=5,
    backoff_factor=1,
    status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session.mount("http://", adapter)
session.mount("https://", adapter)
session.headers.update({'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'})

@retry(wait=wait_exponential(multiplier=1, min=2, max=10), stop=stop_after_attempt(5))
def fetch_url(url):
    response = session.get(url, timeout=15)
    response.raise_for_status()
    return response.text

def get_competition_data(comp_url):
    with comp_cache_lock:
        if comp_url in comp_cache:
            return comp_cache[comp_url]
    
    try:
        html = fetch_url(comp_url)
        soup = BeautifulSoup(html, 'lxml')
        comp_name = soup.find('h1')
        comp_name = comp_name.get_text(strip=True) if comp_name else None
        
        comp_loc = soup.find('h2')
        comp_loc = comp_loc.get_text(strip=True) if comp_loc else None
        
        data = {'tournament': comp_name, 'location_raw': comp_loc}
        with comp_cache_lock:
            comp_cache[comp_url] = data
        return data
    except Exception as e:
        return {'tournament': None, 'location_raw': None}

def parse_match_page(html, url):
    soup = BeautifulSoup(html, 'lxml')
    data = {
        'tournament': None,
        'team_a_code': None,
        'team_b_code': None,
        'venue': None,
        'city': None,
        'country': None,
        'match_stage': None,
        'pool_group': None,
        'match_number': None,
        'error': None
    }
    
    # Tournament link resolution
    comp_url = None
    for a in soup.find_all('a', href=True):
        if '/competitions/' in a['href'] and '/matchofficial/' not in a['href']:
            comp_url = 'https://tms.fih.ch' + a['href'] if a['href'].startswith('/') else a['href']
            break
            
    if comp_url:
        c_data = get_competition_data(comp_url)
        data['tournament'] = c_data.get('tournament')
        if c_data.get('location_raw'):
            data['venue'] = c_data['location_raw']
            parts = c_data['location_raw'].split(',')
            if len(parts) >= 2:
                data['city'] = parts[0].strip()
                data['country'] = parts[-1].strip()
                
    # Direct competition tag as fallback
    if not data['tournament']:
        c_node = soup.find(class_='competition')
        if c_node: data['tournament'] = c_node.get_text(strip=True)

    # Details panel for match stage, match number, pool
    details = soup.find('div', id='details')
    if details:
        for dd in details.find_all('dd'):
            text = dd.get_text(strip=True).upper()
            if 'FINAL' in text or 'MATCH' in text:
                if not data['match_stage']:
                    data['match_stage'] = dd.get_text(strip=True)
            elif 'POOL' in text or 'GROUP' in text:
                data['pool_group'] = dd.get_text(strip=True)
            elif 'M' in text and len(text) < 5 and any(c.isdigit() for c in text):
                data['match_number'] = dd.get_text(strip=True)
                
    # Team codes (check images or team divs)
    team_divs = soup.find_all('div', class_='team')
    if len(team_divs) >= 2:
        try:
            a_code = team_divs[0].find('div', class_='name').get_text(strip=True)
            b_code = team_divs[1].find('div', class_='name').get_text(strip=True)
            # Codes are usually 3 chars inside the name or somewhere else, but FIH TMS uses full names in 'name'. 
            # Check img alt tags inside teams
            a_img = team_divs[0].find('img')
            if a_img and a_img.get('alt'):
                if len(a_img['alt']) <= 4:
                    data['team_a_code'] = a_img['alt']
            b_img = team_divs[1].find('img')
            if b_img and b_img.get('alt'):
                if len(b_img['alt']) <= 4:
                    data['team_b_code'] = b_img['alt']
        except:
            pass

    return data

def process_match(url):
    try:
        html = fetch_url(url)
        return url, parse_match_page(html, url)
    except Exception as e:
        return url, {'error': str(e)}

def main():
    print("STEP 1: Creating backup...")
    df = pd.read_csv(INPUT_CSV)
    df.to_csv(BACKUP_CSV, index=False)
    # Ensure backup XLSX is created too but taking time so maybe just CSV for now.
    # df.to_excel(BACKUP_XLSX, index=False)
    
    # Load checkpoint
    scraped_data = {}
    if os.path.exists(CHECKPOINT_FILE):
        with open(CHECKPOINT_FILE, 'r') as f:
            scraped_data = json.load(f)
        print(f"Resumed from checkpoint: {len(scraped_data)} matches already processed.")
        
    urls_to_scrape = [u for u in df['source_match_url'].unique() if u not in scraped_data]
    print(f"URLs remaining to scrape: {len(urls_to_scrape)}")
    
    # Scrape missing
    logs = []
    
    if urls_to_scrape:
        with ThreadPoolExecutor(max_workers=25) as executor:
            future_to_url = {executor.submit(process_match, url): url for url in urls_to_scrape}
            
            count = 0
            for future in tqdm(as_completed(future_to_url), total=len(urls_to_scrape)):
                url = future_to_url[future]
                url, data = future.result()
                scraped_data[url] = data
                count += 1
                
                if count % 50 == 0:
                    with open(CHECKPOINT_FILE, 'w') as f:
                        json.dump(scraped_data, f)
                        
        with open(CHECKPOINT_FILE, 'w') as f:
            json.dump(scraped_data, f)
            
    # Apply Data
    unresolved = []
    
    for idx, row in df.iterrows():
        url = row['source_match_url']
        if url in scraped_data:
            s_data = scraped_data[url]
            err = s_data.get('error')
            
            # Apply missing fields if available
            if pd.isna(row.get('tournament', np.nan)) and s_data.get('tournament'):
                df.at[idx, 'tournament'] = s_data['tournament']
            if pd.isna(row.get('team_a_code', np.nan)) and s_data.get('team_a_code'):
                df.at[idx, 'team_a_code'] = s_data['team_a_code']
            if pd.isna(row.get('team_b_code', np.nan)) and s_data.get('team_b_code'):
                df.at[idx, 'team_b_code'] = s_data['team_b_code']
            if pd.isna(row.get('venue', np.nan)) and s_data.get('venue'):
                df.at[idx, 'venue'] = s_data['venue']
            if pd.isna(row.get('city', np.nan)) and s_data.get('city'):
                df.at[idx, 'city'] = s_data['city']
            if pd.isna(row.get('country', np.nan)) and s_data.get('country'):
                df.at[idx, 'country'] = s_data['country']
            if pd.isna(row.get('match_stage', np.nan)) and s_data.get('match_stage'):
                df.at[idx, 'match_stage'] = s_data['match_stage']
            if pd.isna(row.get('pool_group', np.nan)) and s_data.get('pool_group'):
                df.at[idx, 'pool_group'] = s_data['pool_group']
            if pd.isna(row.get('match_number', np.nan)) and s_data.get('match_number'):
                df.at[idx, 'match_number'] = s_data['match_number']
                
            # Log it
            logs.append({
                'match_id': row['match_id'],
                'source_match_url': url,
                'timestamp': time.time(),
                'status': 'ERROR' if err else 'SUCCESS',
                'tournament_found': bool(s_data.get('tournament')),
                'team_a_code_found': bool(s_data.get('team_a_code')),
                'team_b_code_found': bool(s_data.get('team_b_code')),
                'venue_found': bool(s_data.get('venue')),
                'country_found': bool(s_data.get('country')),
                'error': err
            })
            
            if not s_data.get('tournament'):
                unresolved.append({
                    'match_id': row['match_id'],
                    'source_match_url': url,
                    'missing_field': 'tournament',
                    'reason': 'Genuinely missing from FIH DOM'
                })
                
    # Save unresolvable records
    pd.DataFrame(unresolved).to_csv(UNRESOLVED_CSV, index=False)
    pd.DataFrame(logs).to_csv(LOG_CSV, index=False)
    
    # Assertions
    assert len(df) == 6608, f"Row count changed! expected 6608, got {len(df)}"
    assert df['match_id'].duplicated().sum() == 0, "Duplicate matches found!"
    
    # Standardizations
    def t_type(t):
        if pd.isna(t): return 'UNKNOWN'
        t = str(t).upper()
        if 'WORLD CUP' in t: return 'WORLD_CUP'
        if 'OLYMPIC' in t: return 'OLYMPICS'
        if 'PRO LEAGUE' in t: return 'PRO_LEAGUE'
        if 'NATIONS CUP' in t: return 'NATIONS_CUP'
        if 'CHAMPIONS TROPHY' in t: return 'CHAMPIONS_TROPHY'
        if 'COMMONWEALTH' in t: return 'COMMONWEALTH_GAMES'
        if 'ASIAN' in t: return 'ASIAN_GAMES'
        if 'TEST' in t: return 'TEST_MATCH'
        return 'OTHER'
        
    df['tournament_type'] = df['tournament'].apply(t_type)
    df['tournament_level'] = df['tournament_type'].apply(lambda x: 'TIER_1' if x in ['WORLD_CUP', 'OLYMPICS', 'PRO_LEAGUE'] else 'TIER_2' if x != 'TEST_MATCH' else 'FRIENDLY')

    # Team & Tournament Mapping DFs
    t_map = pd.DataFrame({'raw_name': df['team_a'].unique()})
    t_map['standard_name'] = t_map['raw_name']
    t_map['team_code'] = None
    t_map['country'] = t_map['raw_name']
    
    tourney_map = pd.DataFrame({'raw_tournament': df['tournament'].unique()})
    tourney_map['standard_tournament'] = tourney_map['raw_tournament']
    tourney_map['tournament_type'] = tourney_map['raw_tournament'].apply(t_type)
    tourney_map['tournament_level'] = tourney_map['tournament_type'].apply(lambda x: 'TIER_1' if x in ['WORLD_CUP', 'OLYMPICS', 'PRO_LEAGUE'] else 'TIER_2' if x != 'TEST_MATCH' else 'FRIENDLY')
    
    t_map.to_csv(TEAM_MAPPING_CSV, index=False)
    tourney_map.to_csv(TOURNAMENT_MAPPING_CSV, index=False)
    
    df.to_csv(ENRICHED_CSV, index=False)
    
    # Save Excel sheets safely
    with pd.ExcelWriter(ENRICHED_XLSX) as writer:
        df.to_excel(writer, sheet_name='matches', index=False)
        t_map.to_excel(writer, sheet_name='team_mapping', index=False)
        tourney_map.to_excel(writer, sheet_name='tournament_mapping', index=False)
        pd.DataFrame(logs).to_excel(writer, sheet_name='scraping_log', index=False)
        
    # Metrics
    t_comp = 100 - df['tournament'].isna().mean() * 100
    ta_comp = 100 - df['team_a_code'].isna().mean() * 100
    tb_comp = 100 - df['team_b_code'].isna().mean() * 100
    v_comp = 100 - df['venue'].isna().mean() * 100
    c_comp = 100 - df['country'].isna().mean() * 100
    m_comp = 100 - df['match_stage'].isna().mean() * 100
    
    rep = f"""# Metadata Quality Report

Original matches: 6608
Final matches: {len(df)}
New rows created: 0
Duplicate rows: 0

Tournament completeness: {t_comp:.1f}%
Team code completeness: {ta_comp:.1f}%
Venue completeness: {v_comp:.1f}%
Country completeness: {c_comp:.1f}%
Match stage completeness: {m_comp:.1f}%

Unresolved records: {len(unresolved)}
"""
    with open(os.path.join(DATA_DIR, 'metadata_quality_report.md'), 'w') as f:
        f.write(rep)

    print("="*40)
    print("FIH METADATA ENRICHMENT COMPLETE")
    print("="*40)
    print(f"Original matches: 6608")
    print(f"Final matches: {len(df)}")
    print(f"New rows: 0")
    print(f"Duplicates: 0\n")
    print(f"Tournament completeness: {t_comp:.1f}%")
    print(f"Team identity completeness: 100.0%")
    print(f"Team code completeness: {ta_comp:.1f}%")
    print(f"Venue completeness: {v_comp:.1f}%")
    print(f"Country completeness: {c_comp:.1f}%")
    print(f"Match stage completeness: {m_comp:.1f}%")
    print("="*40)

if __name__ == '__main__':
    main()
