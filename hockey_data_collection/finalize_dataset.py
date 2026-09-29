import pandas as pd
import os
import json
from hockey_data_collection import config
from hockey_data_collection.processors.normalizer import Normalizer

def finalize():
    print("Starting data validation and formatting...")
    if not os.path.exists(config.RAW_MATCHES_EXCEL):
        print(f"Error: {config.RAW_MATCHES_EXCEL} not found.")
        return
        
    df = pd.read_excel(config.RAW_MATCHES_EXCEL)
    print(f"Loaded {len(df)} total matches.")
    
    # Check for duplicates based on URL
    duplicates = df[df.duplicated(subset=['source_match_url'], keep=False)]
    if not duplicates.empty:
        print(f"Found {len(duplicates)} duplicate records.")
        # df = df.drop_duplicates(subset=['source_match_url'], keep='last')
        # We don't save duplicate report to avoid overwriting variables, just drop duplicates
        df = df.drop_duplicates(subset=['source_match_url'], keep='last')
        
    print(f"Matches after deduplication: {len(df)}")
    
    # 2. Enforce Data Types
    numeric_cols = [
        'team_a_score', 'team_b_score', 'goal_difference'
    ]
    
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')
            
    # Convert dates
    if 'match_date_raw' in df.columns:
        df['match_date'] = pd.to_datetime(df['match_date_raw'], errors='coerce').dt.date
        
    # 3. Standardize Team Names
    normalizer = Normalizer()
    
    # We apply normalizer to team_a, team_b, winner, loser
    for col in ['team_a', 'team_b', 'winner', 'loser']:
        if col in df.columns:
            df[col] = df[col].apply(lambda x: normalizer.normalize_team_name(str(x)) if pd.notnull(x) else x)
            
    # Check for blank vital fields
    conflicts = df[df['winner'].isnull() | df['team_a_score'].isnull()]
    if not conflicts.empty:
        print(f"Found {len(conflicts)} records with missing vital stats.")
        
    # 4. Final Save
    df.to_excel(config.RAW_MATCHES_EXCEL, index=False)
    
    csv_path = str(config.RAW_MATCHES_EXCEL).replace('.xlsx', '.csv')
    df.to_csv(csv_path, index=False)
    print(f"FINALIZED: {len(df)} completely processed matches saved to {config.RAW_MATCHES_EXCEL}")

if __name__ == '__main__':
    finalize()
