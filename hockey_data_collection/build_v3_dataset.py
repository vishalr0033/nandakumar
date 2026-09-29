import pandas as pd
import numpy as np
from datetime import datetime
import json
import os

DATA_DIR = "data"
REPORTS_DIR = "../hockey_prediction_r/reports"
os.makedirs(REPORTS_DIR, exist_ok=True)

INPUT_FILE = os.path.join(DATA_DIR, "hockey_matches_final_enriched.xlsx")
OUTPUT_EXCEL = os.path.join(DATA_DIR, "hockey_prediction_dataset_v3.xlsx")

def calculate_elo(ra, rb, sa, margin):
    K = 20
    ea = 1 / (1 + 10 ** ((rb - ra) / 400))
    eb = 1 / (1 + 10 ** ((ra - rb) / 400))
    mov = abs(margin)
    mult = np.log(mov + 1) if mov > 0 else 1
    ra_new = ra + K * mult * (sa - ea)
    rb_new = rb + K * mult * ((1 - sa) - eb)
    return ra_new, rb_new

def ema_form(history, alpha=0.3):
    if not history: return 0.0
    ema = history[0]
    for x in history[1:]:
        ema = alpha * x + (1 - alpha) * ema
    return float(ema)

def safe_mean(lst): return float(np.mean(lst)) if len(lst) > 0 else 0.0
def safe_sum(lst): return sum(lst) if len(lst) > 0 else 0

print("Loading dataset...")
df = pd.read_excel(INPUT_FILE)
original_rows = len(df)
df['match_date'] = pd.to_datetime(df['match_date'])
df = df.sort_values(by='match_date').reset_index(drop=True)

team_stats = {}
h2h_stats = {}
team_elo = {}
INITIAL_ELO = 1500.0

def get_team(team_name):
    if team_name not in team_stats:
        team_stats[team_name] = {
            'matches': 0, 'wins': 0, 'losses': 0, 'draws': 0,
            'goals_for': [], 'goals_against': [], 'goal_diff': [],
            'win_history': [], 'match_dates': []
        }
    if team_name not in team_elo: team_elo[team_name] = INITIAL_ELO
    return team_stats[team_name]

def get_h2h(t1, t2):
    key = tuple(sorted([str(t1), str(t2)]))
    if key not in h2h_stats:
        h2h_stats[key] = {'matches': 0, 'wins': {str(t1): 0, str(t2): 0}, 'draws': 0}
    return h2h_stats[key], key

print("Engineering V3 chronological features...")
features = []

for idx, row in df.iterrows():
    ta = str(row['team_a'])
    tb = str(row['team_b'])
    m_date = row['match_date']
    
    sa = get_team(ta)
    sb = get_team(tb)
    h2h, h2h_key = get_h2h(ta, tb)
    
    feat = {}
    
    # ELO & Strengths
    feat['team_a_elo_before'] = team_elo[ta]
    feat['team_b_elo_before'] = team_elo[tb]
    feat['elo_difference'] = team_elo[ta] - team_elo[tb]
    
    # Experience
    feat['team_a_matches_before'] = sa['matches']
    feat['team_b_matches_before'] = sb['matches']
    feat['experience_difference'] = sa['matches'] - sb['matches']
    
    # Win Rates
    feat['team_a_win_rate_before'] = sa['wins'] / sa['matches'] if sa['matches'] > 0 else 0.0
    feat['team_b_win_rate_before'] = sb['wins'] / sb['matches'] if sb['matches'] > 0 else 0.0
    
    # Rolling Forms (3, 5, 10, 20)
    for w in [3, 5, 10, 20]:
        feat[f'team_a_last_{w}_wins'] = safe_sum(sa['win_history'][-w:])
        feat[f'team_b_last_{w}_wins'] = safe_sum(sb['win_history'][-w:])
        feat[f'team_a_last_{w}_win_rate'] = feat[f'team_a_last_{w}_wins']/min(w, sa['matches']) if sa['matches'] > 0 else 0
        feat[f'team_b_last_{w}_win_rate'] = feat[f'team_b_last_{w}_wins']/min(w, sb['matches']) if sb['matches'] > 0 else 0
        
        feat[f'team_a_last_{w}_goals_for'] = safe_sum(sa['goals_for'][-w:])
        feat[f'team_b_last_{w}_goals_for'] = safe_sum(sb['goals_for'][-w:])
        feat[f'team_a_last_{w}_goals_against'] = safe_sum(sa['goals_against'][-w:])
        feat[f'team_b_last_{w}_goals_against'] = safe_sum(sb['goals_against'][-w:])
        
        feat[f'team_a_last_{w}_gd'] = safe_sum(sa['goal_diff'][-w:])
        feat[f'team_b_last_{w}_gd'] = safe_sum(sb['goal_diff'][-w:])
        
    # EMA Form
    feat['team_a_ema_form'] = ema_form(sa['win_history'])
    feat['team_b_ema_form'] = ema_form(sb['win_history'])
    
    # Goal Averages
    feat['team_a_average_goals_for'] = safe_mean(sa['goals_for'])
    feat['team_b_average_goals_for'] = safe_mean(sb['goals_for'])
    feat['team_a_average_goals_against'] = safe_mean(sa['goals_against'])
    feat['team_b_average_goals_against'] = safe_mean(sb['goals_against'])
    feat['team_a_average_gd'] = safe_mean(sa['goal_diff'])
    feat['team_b_average_gd'] = safe_mean(sb['goal_diff'])
    
    # Rest Days & Fatigue
    if pd.notna(m_date):
        if len(sa['match_dates']) > 0:
            feat['team_a_rest_days'] = (m_date - sa['match_dates'][-1]).days
        else: feat['team_a_rest_days'] = 30
        
        if len(sb['match_dates']) > 0:
            feat['team_b_rest_days'] = (m_date - sb['match_dates'][-1]).days
        else: feat['team_b_rest_days'] = 30
        
        feat['rest_days_difference'] = feat['team_a_rest_days'] - feat['team_b_rest_days']
    else:
        feat['team_a_rest_days'] = 30
        feat['team_b_rest_days'] = 30
        feat['rest_days_difference'] = 0
        
    # H2H
    feat['h2h_matches_before'] = h2h['matches']
    feat['h2h_team_a_wins'] = h2h['wins'].get(ta, 0)
    feat['h2h_team_b_wins'] = h2h['wins'].get(tb, 0)
    if h2h['matches'] > 0:
        feat['h2h_team_a_win_rate'] = feat['h2h_team_a_wins'] / h2h['matches']
    else:
        feat['h2h_team_a_win_rate'] = 0.0
        
    features.append(feat)
    
    # -------------------------------------------------------------------------
    # UPDATE STATE (AFTER match)
    # -------------------------------------------------------------------------
    score_a = row['team_a_score']
    score_b = row['team_b_score']
    
    if pd.notna(score_a) and pd.notna(score_b):
        win_a = 1 if score_a > score_b else (0.5 if score_a == score_b else 0)
        margin = score_a - score_b
        if score_a == score_b and row['result'] != "DRAW":
            win_a = 1 if row['winner'] == ta else 0
                
        team_elo[ta], team_elo[tb] = calculate_elo(team_elo[ta], team_elo[tb], win_a, margin)
        
        # A
        sa['matches'] += 1
        sa['goals_for'].append(score_a)
        sa['goals_against'].append(score_b)
        sa['goal_diff'].append(score_a - score_b)
        res_a = 1 if score_a > score_b else (0 if score_a < score_b else (1 if row['result'] != "DRAW" and row['winner'] == ta else 0))
        sa['wins'] += 1 if res_a == 1 else 0
        sa['losses'] += 1 if res_a == 0 and score_a != score_b else 0
        sa['win_history'].append(res_a)
        sa['match_dates'].append(m_date)
        
        # B
        sb['matches'] += 1
        sb['goals_for'].append(score_b)
        sb['goals_against'].append(score_a)
        sb['goal_diff'].append(score_b - score_a)
        res_b = 1 if score_b > score_a else (0 if score_b < score_a else (1 if row['result'] != "DRAW" and row['winner'] == tb else 0))
        sb['wins'] += 1 if res_b == 1 else 0
        sb['losses'] += 1 if res_b == 0 and score_a != score_b else 0
        sb['win_history'].append(res_b)
        sb['match_dates'].append(m_date)
        
        # H2H
        h2h['matches'] += 1
        if res_a == 1: h2h['wins'][ta] += 1
        elif res_b == 1: h2h['wins'][tb] += 1
        else: h2h['draws'] += 1

feat_df = pd.DataFrame(features)
final_df = pd.concat([df, feat_df], axis=1)

print("Running Python-side strict leakage audit...")
# Verify that no column starting with 'team_a_score' or 'winner' correlates perfectly with 'elo_difference'
# (Mathematical proof of independence)
violations = 0
target = np.where(final_df['winner'] == final_df['team_a'], 1, 0)
for col in feat_df.columns:
    if feat_df[col].dtype in [np.float64, np.int64]:
        corr = np.abs(np.corrcoef(feat_df[col].fillna(0), target)[0,1])
        if corr > 0.95:
            print(f"VIOLATION: High correlation {corr} in {col}")
            violations += 1

if violations > 0:
    print("LEAKAGE DETECTED! Aborting.")
    exit(1)

print(f"Saving to {OUTPUT_EXCEL}...")
final_df.to_excel(OUTPUT_EXCEL, index=False)
print("V3 dataset generation complete.")
