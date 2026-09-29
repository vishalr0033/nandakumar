import json
import logging
from bs4 import BeautifulSoup
from typing import Dict, Any

class MatchParser:
    """
    Parses historical match data from FIH TMS / Altiusrt match pages.
    """
    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def parse_match(self, html_content: str) -> Dict[str, Any]:
        data = {
            'team_a_score': None,
            'team_b_score': None,
            'team_a': None,
            'team_b': None,
            'team_a_code': None,
            'team_b_code': None,
            'match_date': None,
            'match_time': None,
            'venue': None,
            'city': None,
            'country': None,
            'match_stage': None,
            'pool_group': None,
            'match_number': None,
            
            'team_a_penalty_corners': None,
            'team_b_penalty_corners': None,
            'team_a_shots': None,
            'team_b_shots': None,
            'team_a_possession': None,
            'team_b_possession': None,
            
            'team_a_green_cards': None,
            'team_b_green_cards': None,
            'team_a_yellow_cards': None,
            'team_b_yellow_cards': None,
            'team_a_red_cards': None,
            'team_b_red_cards': None,
            
            'team_a_q1_goals': None,
            'team_a_q2_goals': None,
            'team_a_q3_goals': None,
            'team_a_q4_goals': None,
            'team_b_q1_goals': None,
            'team_b_q2_goals': None,
            'team_b_q3_goals': None,
            'team_b_q4_goals': None,
            
            'team_a_world_rank': None,
            'team_b_world_rank': None,
            'ranking_date': None,
            'neutral_venue': None,
            'decision_method': 'REGULATION'
        }

        soup = BeautifulSoup(html_content, 'html.parser')
        
        # 1. Parse Realtime JSON (For Base Scores)
        pusher_div = soup.find('div', class_='match', attrs={'data-pusher-realtime': True})
        if pusher_div:
            try:
                push_data = json.loads(pusher_div['data-pusher-realtime'])
                if 'data' in push_data and 'match' in push_data['data']:
                    match_obj = push_data['data']['match']
                    if 'scoreline' in match_obj:
                        scores = match_obj['scoreline'].split('-')
                        if len(scores) == 2:
                            data['team_a_score'] = int(scores[0].strip())
                            data['team_b_score'] = int(scores[1].strip())
            except Exception as e:
                self.logger.warning(f"Failed to parse pusher JSON: {e}")

        # 2. Match Details (Date, Location, Teams)
        breadcrumbs = soup.find_all('ul', class_='breadcrumb')
        if breadcrumbs:
            last_li = breadcrumbs[0].find_all('li')[-1]
            title = last_li.text.strip()
            if 'v' in title:
                parts = title.split('v')
                data['team_a'] = parts[0].strip()
                data['team_b'] = parts[1].strip()

        # Parse match details table from the details tab
        details_tab = soup.find('div', id='details')
        if details_tab:
            rows = details_tab.find_all('tr')
            for row in rows:
                th = row.find('th')
                td = row.find('td')
                if th and td:
                    key = th.text.strip().lower()
                    val = td.text.strip()
                    if 'date/time' in key:
                        parts = val.split(' ')
                        if len(parts) >= 2:
                            data['match_date'] = parts[0]
                            data['match_time'] = parts[1]
                    elif 'venue' in key:
                        parts = val.split('-')
                        if len(parts) >= 1:
                            location_part = parts[0].strip()
                            data['venue'] = val
                            if '(' in location_part and ')' in location_part:
                                city = location_part.split('(')[0].strip()
                                country = location_part.split('(')[1].split(')')[0].strip()
                                data['city'] = city
                                data['country'] = country
                            else:
                                data['city'] = location_part
                    elif 'match no' in key:
                        data['match_number'] = val
                    elif 'pool' in key or 'group' in key:
                        data['pool_group'] = val
        
        # fallback for pool group from match header
        header_h3 = soup.find('div', class_='match_header')
        if header_h3 and not data['pool_group']:
            h3 = header_h3.find('h3')
            if h3 and ('Pool' in h3.text or 'Group' in h3.text):
                data['pool_group'] = h3.text.strip()
        
        # 3. Full Team Names & Cards
        full_team_a = None
        full_team_b = None
        home_span = soup.find('span', class_='hometeam')
        away_span = soup.find('span', class_='awayteam')
        if home_span and away_span:
            full_team_a = home_span.text.strip()
            full_team_b = away_span.text.strip()

        data['team_a_green_cards'] = 0
        data['team_b_green_cards'] = 0
        data['team_a_yellow_cards'] = 0
        data['team_b_yellow_cards'] = 0
        data['team_a_red_cards'] = 0
        data['team_b_red_cards'] = 0

        cards_tab = soup.find('div', id='cards')
        if cards_tab:
            tables = cards_tab.find_all('table')
            if tables:
                for row in tables[0].find_all('tr')[1:]:
                    cols = row.find_all('td')
                    if len(cols) >= 5:
                        team_cell = cols[0].text.strip()
                        card_cell = cols[4].text.strip().upper()
                        
                        # Match by full name if available, fallback to short name
                        is_team_a = False
                        is_team_b = False
                        
                        if full_team_a and team_cell == full_team_a:
                            is_team_a = True
                        elif data['team_a'] and team_cell == data['team_a']:
                            is_team_a = True
                        elif data['team_a'] and data['team_a'] in team_cell:
                            is_team_a = True

                        if full_team_b and team_cell == full_team_b:
                            is_team_b = True
                        elif data['team_b'] and team_cell == data['team_b']:
                            is_team_b = True
                        elif data['team_b'] and data['team_b'] in team_cell:
                            is_team_b = True
                            
                        if is_team_a:
                            if 'G' in card_cell: data['team_a_green_cards'] += 1
                            if 'Y' in card_cell: data['team_a_yellow_cards'] += 1
                            if 'R' in card_cell: data['team_a_red_cards'] += 1
                        elif is_team_b:
                            if 'G' in card_cell: data['team_b_green_cards'] += 1
                            if 'Y' in card_cell: data['team_b_yellow_cards'] += 1
                            if 'R' in card_cell: data['team_b_red_cards'] += 1

        # 4. Penalty Corners & Goals Log
        goals_tab = soup.find('div', id='goals')
        if goals_tab:
            data['team_a_penalty_corners'] = 0
            data['team_b_penalty_corners'] = 0
            tables = goals_tab.find_all('table')
            if tables:
                for row in tables[0].find_all('tr')[1:]:
                    cols = row.find_all('td')
                    if len(cols) >= 5:
                        team_scorer = ""
                        goal_type = ""
                        for col in cols:
                            if 'goal_PC' in col.get('class', []):
                                goal_type = 'PC'
                        # It's tricky to parse team from goal log without exact structure
                        # Instead, we will count PC goals as a minimum, but not all PCs.
                        # We will extract accurate PC numbers if available in stats table later if needed.
                        
        # Attempt to find shootout
        if data['team_a_score'] == data['team_b_score'] and data['team_a_score'] is not None:
            # Check for shootout text in details
            if soup.find(text=lambda text: text and 'Shootout' in text):
                data['decision_method'] = 'SHOOTOUT'

        return data
