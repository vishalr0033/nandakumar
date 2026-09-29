import pandas as pd
from hockey_data_collection import config

class Normalizer:
    def __init__(self):
        self.team_mapping = self._load_mapping()
        
    def _load_mapping(self):
        if config.TEAM_MAPPING_CSV.exists():
            return pd.read_csv(config.TEAM_MAPPING_CSV).set_index('raw_name')['standard_name'].to_dict()
        return {}

    def normalize_team_name(self, raw_name):
        return self.team_mapping.get(raw_name, raw_name)
        
    def process_match(self, match):
        """Normalizes team names, calculates winner/loser/result, and formats fields."""
        if 'team_a' in match:
            match['team_a_code'] = match['team_a']
            match['team_a'] = self.normalize_team_name(match['team_a'])
        if 'team_b' in match:
            match['team_b_code'] = match['team_b']
            match['team_b'] = self.normalize_team_name(match['team_b'])
            
        try:
            if 'team_a_score' in match and 'team_b_score' in match:
                score_a = int(match['team_a_score'])
                score_b = int(match['team_b_score'])
                match['goal_difference'] = abs(score_a - score_b)
                
                if score_a > score_b:
                    match['winner'] = match['team_a']
                    match['loser'] = match['team_b']
                    match['result'] = 'A_WIN'
                elif score_b > score_a:
                    match['winner'] = match['team_b']
                    match['loser'] = match['team_a']
                    match['result'] = 'B_WIN'
                else:
                    match['result'] = 'DRAW'
                    match['winner'] = None
                    match['loser'] = None
                    
                match['decision_method'] = 'REGULATION' # Defaulting, assuming no shootout parsed
        except ValueError:
            pass

        # Generate match_id
        if 'match_date_raw' in match and 'team_a' in match and 'team_b' in match:
            safe_date = str(match['match_date_raw']).replace(' ', '_').replace('-', '')
            match['match_id'] = f"{safe_date}_{match['team_a']}_{match['team_b']}_{match.get('tournament', '')}"
            
        return match
