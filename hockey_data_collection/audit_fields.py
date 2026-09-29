import pandas as pd
import requests
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor, as_completed
import random
import re

def parse_match(url):
    try:
        r = requests.get(url, timeout=10)
        soup = BeautifulSoup(r.text, 'lxml')
        
        found = {
            'ranking': False,
            'match_stage': False,
            'pool_group': False,
            'match_number': False,
            'penalty_corners': False,
            'shots': False,
            'possession': False,
            'cards': False,
            'quarter_goals': False
        }
        
        text = soup.get_text().upper()
        
        # Check text heuristics
        if 'RANK' in text or 'WORLD RANKING' in text: found['ranking'] = True
        if 'SHOTS' in text or 'SHOT ON' in text: found['shots'] = True
        if 'POSSESSION' in text: found['possession'] = True
        
        # Details panel for stage/pool/number
        details = soup.find('div', id='details')
        if details:
            for dd in details.find_all('dd'):
                dt = dd.get_text(strip=True).upper()
                if 'FINAL' in dt or 'MATCH' in dt: found['match_stage'] = True
                if 'POOL' in dt or 'GROUP' in dt: found['pool_group'] = True
                if 'M' in dt and len(dt) < 5 and any(c.isdigit() for c in dt): found['match_number'] = True
                
        # Panels for cards and corners
        panels = soup.find_all('div', class_='panel-heading')
        for p in panels:
            t = p.get_text(strip=True).upper()
            if 'CARDS' in t: found['cards'] = True
            if 'PENALTY CORNER' in t: found['penalty_corners'] = True
            
        # Quarter goals
        if '1ST QUARTER' in text or 'Q1' in text: found['quarter_goals'] = True
            
        return found
    except Exception as e:
        return None

def main():
    df = pd.read_csv('data/hockey_matches_metadata_enriched.csv')
    urls = df['source_match_url'].tolist()
    
    # Take stratified sample (start, middle, end)
    sample = urls[:15] + urls[len(urls)//2 : len(urls)//2 + 20] + urls[-15:]
    
    results = {
        'ranking': 0, 'match_stage': 0, 'pool_group': 0, 'match_number': 0,
        'penalty_corners': 0, 'shots': 0, 'possession': 0, 'cards': 0, 'quarter_goals': 0
    }
    
    valid = 0
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(parse_match, u) for u in sample]
        for f in as_completed(futures):
            res = f.result()
            if res:
                valid += 1
                for k, v in res.items():
                    if v: results[k] += 1
                    
    print(f"Audit Complete. Evaluated {valid} matches.")
    print("Found counts:")
    for k, v in results.items():
        print(f"{k}: {v}/{valid} ({(v/valid)*100:.1f}%)")

if __name__ == '__main__':
    main()
