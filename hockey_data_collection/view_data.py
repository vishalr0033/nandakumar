import pandas as pd
from tabulate import tabulate
import os
import sys

def main():
    excel_path = "data/raw_matches_v2.xlsx"
    if not os.path.exists(excel_path):
        print(f"File not found: {excel_path}")
        sys.exit(1)
        
    df = pd.read_excel(excel_path)
    
    print("========================================")
    print(f"Total Matches Collected: {len(df)}")
    print("========================================")
    
    if len(df) >= 1000:
        print("SUCCESS: Collected 1000+ matches as required for the ML model!")
    else:
        print(f"WARNING: Collected {len(df)} matches. Still need {1000 - len(df)} more.")
        
    print("\nFirst 10 records:")
    # Print a few key columns to fit in the terminal
    display_cols = ['tournament', 'match_date_raw', 'team_a', 'team_a_score', 'team_b_score', 'team_b', 'winner']
    available_cols = [c for c in display_cols if c in df.columns]
    
    print(tabulate(df[available_cols].head(10), headers='keys', tablefmt='psql', showindex=False))

if __name__ == "__main__":
    main()
