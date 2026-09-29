import pandas as pd
import numpy as np
from datetime import datetime
import os
import math

DATA_DIR = "data"
REPORTS_DIR = "../hockey_prediction_r/reports"
os.makedirs(REPORTS_DIR, exist_ok=True)

INPUT_FILE = os.path.join(DATA_DIR, "hockey_matches_final_enriched.xlsx")
OUTPUT_EXCEL = os.path.join(DATA_DIR, "hockey_prediction_dataset_v4.xlsx")

def calculate_elo(ra, rb, sa, margin, K=20):
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
def safe_std(lst): return float(np.std(lst)) if len(lst) > 1 else 0.0

print("Loading dataset...")
df = pd.read_excel(INPUT_FILE)
df['match_date'] = pd.to_datetime(df['match_date'])
df = df.sort_values(by='match_date').reset_index(drop=True)

team_stats = {}
h2h_stats = {}

def get_team(team_name):
    if team_name not in team_stats:
        team_stats[team_name] = {
            'matches': 0, 'wins': 0, 'losses': 0, 'draws': 0,
            'goals_for': [], 'goals_against': [], 'goal_diff': [],
            'win_history': [], 'match_dates': [],
            'opponent_elos': [],
            'elo_k10': 1500.0,
            'elo_k20': 1500.0,
            'elo_k30': 1500.0
        }
    return team_stats[team_name]

def get_h2h(t1, t2):
    key = tuple(sorted([str(t1), str(t2)]))
    if key not in h2h_stats:
        h2h_stats[key] = {'matches': 0, 'wins': {str(t1): 0, str(t2): 0}, 'draws': 0, 'history': []}
    return h2h_stats[key], key

print("Engineering V4 chronological features...")
features = []

for idx, row in df.iterrows():
    ta = str(row['team_a'])
    tb = str(row['team_b'])
    m_date = row['match_date']
    
    sa = get_team(ta)
    sb = get_team(tb)
    h2h, h2h_key = get_h2h(ta, tb)
    
    feat = {}
    
    # 1. Multi-Config ELO
    feat['team_a_elo_k10'] = sa['elo_k10']
    feat['team_b_elo_k10'] = sb['elo_k10']
    feat['elo_diff_k10'] = sa['elo_k10'] - sb['elo_k10']
    
    feat['team_a_elo_k20'] = sa['elo_k20']
    feat['team_b_elo_k20'] = sb['elo_k20']
    feat['elo_diff_k20'] = sa['elo_k20'] - sb['elo_k20']
    
    feat['team_a_elo_k30'] = sa['elo_k30']
    feat['team_b_elo_k30'] = sb['elo_k30']
    feat['elo_diff_k30'] = sa['elo_k30'] - sb['elo_k30']
    
    feat['elo_ratio_k20'] = sa['elo_k20'] / sb['elo_k20'] if sb['elo_k20'] > 0 else 1.0
    
    # 2. Experience
    feat['team_a_matches_before'] = sa['matches']
    feat['team_b_matches_before'] = sb['matches']
    feat['exp_diff'] = sa['matches'] - sb['matches']
    
    # 3. Rolling Forms (2, 3, 5, 8, 10, 15, 20, 30)
    windows = [2, 3, 5, 8, 10, 15, 20, 30]
    for w in windows:
        for t_prefix, s in [('team_a', sa), ('team_b', sb)]:
            w_actual = min(w, s['matches'])
            
            feat[f'{t_prefix}_last_{w}_wins'] = safe_sum(s['win_history'][-w:])
            feat[f'{t_prefix}_last_{w}_win_rate'] = feat[f'{t_prefix}_last_{w}_wins'] / w_actual if w_actual > 0 else 0.0
            
            feat[f'{t_prefix}_last_{w}_gf'] = safe_sum(s['goals_for'][-w:])
            feat[f'{t_prefix}_last_{w}_ga'] = safe_sum(s['goals_against'][-w:])
            feat[f'{t_prefix}_last_{w}_gd'] = safe_sum(s['goal_diff'][-w:])
            
            # Points rate (Win=3, Draw=1, Loss=0) - wait, win_history is 1 for win, 0 for loss/draw. Let's stick to win rate.
            
            # Opponent strength adjusted (average ELO of opponents in last w matches)
            feat[f'{t_prefix}_last_{w}_opp_elo'] = safe_mean(s['opponent_elos'][-w:])
    
    # 4. Momentum (Short-term minus Long-term)
    feat['team_a_momentum_win_rate'] = feat.get('team_a_last_5_win_rate', 0) - feat.get('team_a_last_20_win_rate', 0)
    feat['team_b_momentum_win_rate'] = feat.get('team_b_last_5_win_rate', 0) - feat.get('team_b_last_20_win_rate', 0)
    feat['team_a_momentum_gd'] = feat.get('team_a_last_5_gd', 0) - feat.get('team_a_last_20_gd', 0)
    feat['team_b_momentum_gd'] = feat.get('team_b_last_5_gd', 0) - feat.get('team_b_last_20_gd', 0)
    
    # 5. Consistency
    feat['team_a_consistency_gd_10'] = safe_std(sa['goal_diff'][-10:])
    feat['team_b_consistency_gd_10'] = safe_std(sb['goal_diff'][-10:])
    
    # 6. EWMA Form
    feat['team_a_ewma_win'] = ema_form(sa['win_history'], alpha=0.15)
    feat['team_b_ewma_win'] = ema_form(sb['win_history'], alpha=0.15)
    feat['team_a_ewma_gd'] = ema_form(sa['goal_diff'], alpha=0.15)
    feat['team_b_ewma_gd'] = ema_form(sb['goal_diff'], alpha=0.15)
    
    # 7. Fatigue / Rest (Days since last match, matches in last 7, 14, 30 days)
    if pd.notna(m_date):
        if len(sa['match_dates']) > 0:
            feat['team_a_rest_days'] = (m_date - sa['match_dates'][-1]).days
        else: feat['team_a_rest_days'] = 30
        
        if len(sb['match_dates']) > 0:
            feat['team_b_rest_days'] = (m_date - sb['match_dates'][-1]).days
        else: feat['team_b_rest_days'] = 30
        
        # Matches in last X days
        for d in [7, 14, 30]:
            feat[f'team_a_matches_last_{d}d'] = sum(1 for md in sa['match_dates'] if (m_date - md).days <= d)
            feat[f'team_b_matches_last_{d}d'] = sum(1 for md in sb['match_dates'] if (m_date - md).days <= d)
    else:
        feat['team_a_rest_days'] = 30
        feat['team_b_rest_days'] = 30
        for d in [7, 14, 30]:
            feat[f'team_a_matches_last_{d}d'] = 0
            feat[f'team_b_matches_last_{d}d'] = 0
            
    feat['rest_days_diff'] = feat['team_a_rest_days'] - feat['team_b_rest_days']
    
    # 8. Recency-Aware H2H
    feat['h2h_matches_before'] = h2h['matches']
    feat['h2h_a_wins'] = h2h['wins'].get(ta, 0)
    feat['h2h_b_wins'] = h2h['wins'].get(tb, 0)
    feat['h2h_a_win_rate'] = feat['h2h_a_wins'] / h2h['matches'] if h2h['matches'] > 0 else 0.0
    
    for w in [3, 5, 10]:
        recent_h2h = h2h['history'][-w:]
        w_actual = len(recent_h2h)
        a_recent_wins = sum(1 for res in recent_h2h if res == ta)
        b_recent_wins = sum(1 for res in recent_h2h if res == tb)
        feat[f'h2h_last_{w}_a_win_rate'] = a_recent_wins / w_actual if w_actual > 0 else 0.0
        feat[f'h2h_last_{w}_b_win_rate'] = b_recent_wins / w_actual if w_actual > 0 else 0.0
    
    features.append(feat)
    
    # -------------------------------------------------------------------------
    # UPDATE STATE (AFTER match)
    # -------------------------------------------------------------------------
    score_a = row['team_a_score']
    score_b = row['team_b_score']
    
    if pd.notna(score_a) and pd.notna(score_b):
        win_a_elo = 1 if score_a > score_b else (0.5 if score_a == score_b else 0)
        margin = score_a - score_b
        if score_a == score_b and row['result'] != "DRAW":
            win_a_elo = 1 if row['winner'] == ta else 0
                
        # Update ELOs
        sa['elo_k10'], sb['elo_k10'] = calculate_elo(sa['elo_k10'], sb['elo_k10'], win_a_elo, margin, K=10)
        sa['elo_k20'], sb['elo_k20'] = calculate_elo(sa['elo_k20'], sb['elo_k20'], win_a_elo, margin, K=20)
        sa['elo_k30'], sb['elo_k30'] = calculate_elo(sa['elo_k30'], sb['elo_k30'], win_a_elo, margin, K=30)
        
        # Win Flags
        res_a = 1 if score_a > score_b else (0 if score_a < score_b else (1 if row['result'] != "DRAW" and row['winner'] == ta else 0))
        res_b = 1 if score_b > score_a else (0 if score_b < score_a else (1 if row['result'] != "DRAW" and row['winner'] == tb else 0))
        
        # A
        sa['matches'] += 1
        sa['goals_for'].append(score_a)
        sa['goals_against'].append(score_b)
        sa['goal_diff'].append(score_a - score_b)
        sa['wins'] += 1 if res_a == 1 else 0
        sa['losses'] += 1 if res_a == 0 and score_a != score_b else 0
        sa['win_history'].append(res_a)
        sa['match_dates'].append(m_date)
        sa['opponent_elos'].append(sb['elo_k20'])
        
        # B
        sb['matches'] += 1
        sb['goals_for'].append(score_b)
        sb['goals_against'].append(score_a)
        sb['goal_diff'].append(score_b - score_a)
        sb['wins'] += 1 if res_b == 1 else 0
        sb['losses'] += 1 if res_b == 0 and score_a != score_b else 0
        sb['win_history'].append(res_b)
        sb['match_dates'].append(m_date)
        sb['opponent_elos'].append(sa['elo_k20'])
        
        # H2H
        h2h['matches'] += 1
        if res_a == 1: 
            h2h['wins'][ta] += 1
            h2h['history'].append(ta)
        elif res_b == 1: 
            h2h['wins'][tb] += 1
            h2h['history'].append(tb)
        else: 
            h2h['draws'] += 1
            h2h['history'].append('DRAW')

feat_df = pd.DataFrame(features)
final_df = pd.concat([df, feat_df], axis=1)

print("Running Python-side strict leakage audit...")
# Verify that no column starting with 'team_a_score' or 'winner' correlates perfectly with 'elo_diff_k20'
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
print("V4 dataset generation complete.")
