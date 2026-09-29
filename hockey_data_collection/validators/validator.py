import pandas as pd
from hockey_data_collection import config

class Validator:
    def validate_data(self, matches):
        valid = []
        invalid = []
        
        for m in matches:
            if not m.get('team_a') or not m.get('team_b'):
                invalid.append(m)
                continue
            if m['team_a'] == m['team_b']:
                invalid.append(m)
                continue
            if 'team_a_score' in m and 'team_b_score' in m:
                try:
                    sa, sb = int(m['team_a_score']), int(m['team_b_score'])
                    if sa < 0 or sb < 0:
                        invalid.append(m)
                        continue
                except ValueError:
                    invalid.append(m)
                    continue
            valid.append(m)
            
        with open(config.VALIDATION_REPORT_TXT, "w") as f:
            f.write(f"Total scraped records: {len(matches)}\n")
            f.write(f"Valid records: {len(valid)}\n")
            f.write(f"Invalid records: {len(invalid)}\n")
            
        return valid, invalid
