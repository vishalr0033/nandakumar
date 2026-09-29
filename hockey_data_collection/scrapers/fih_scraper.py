from hockey_data_collection.scrapers.base_scraper import BaseScraper
from hockey_data_collection import config

class FihScraper(BaseScraper):
    def get_source_name(self):
        return "FIH TMS"
        
    def discover_competitions(self):
        """Finds all Senior Mens Outdoor competitions by probing sequential IDs."""
        self.logger.info("Discovering competitions using sequential ID probe...")
        competitions = []
        
        # Load from checkpoint if exists
        import os
        import json
        checkpoint_file = "data/checkpoint_comps.json"
        if os.path.exists(checkpoint_file):
            with open(checkpoint_file, 'r') as f:
                competitions = json.load(f)
            self.logger.info(f"Loaded {len(competitions)} competitions from checkpoint.")
            return competitions

        # Probe IDs (roughly 1 to 2000 covers most history up to 2026)
        # We will do a smaller range for performance, e.g., 1000 to 2000.
        # FIH TMS started around 2013 with IDs in the 100s, but we will go 1 to 2000.
        for comp_id in range(1, 2000):
            url = f"{config.TMS_COMPETITIONS_URL}/{comp_id}"
            try:
                soup = self.fetch_url(url)
                header = soup.find('div', class_='competition_header')
                if header:
                    text = header.text.strip().replace('\n', ' ')
                    # Strictly "Senior Mens Outdoor" or equivalent men's outdoor
                    if "Mens Outdoor" in text and "Under" not in text and "Youth" not in text and "Junior" not in text:
                        comp_name = soup.find('h2').text.strip() if soup.find('h2') else f"Competition {comp_id}"
                        competitions.append({
                            'name': comp_name,
                            'url': f"/competitions/{comp_id}",
                            'type': "Senior Mens Outdoor"
                        })
                        self.logger.info(f"Found match: {comp_name}")
            except Exception as e:
                # 404 or other errors for invalid IDs
                pass
                
        self.logger.info(f"Discovered {len(competitions)} Senior Mens Outdoor competitions.")
        
        with open(checkpoint_file, 'w') as f:
            json.dump(competitions, f)
            
        return competitions
            
    def get_matches_for_competition(self, comp):
        """Extracts match URLs from a competition's matches page."""
        try:
            url_to_fetch = comp.get('matches_url') or (comp['url'] + '/matches')
            if not url_to_fetch.startswith('http'):
                url_to_fetch = "https://tms.fih.ch" + url_to_fetch
            soup = self.fetch_url(url_to_fetch)
            match_links = []
            
            # Find all panels containing match info
            panels = soup.find_all('div', class_='panel')
            for panel in panels:
                # Find the a tag containing the match link
                link = panel.find('a', href=lambda href: href and "/matches/" in href)
                if link:
                    match_links.append(link['href'])
                    
            return match_links
        except Exception as e:
            self.logger.error(f"Failed to get matches for {comp['name']}: {e}")
            return []

    def fetch_match_html(self, match_url):
        """Fetches the HTML for a single match."""
        try:
            return self.fetch_url(match_url)
        except Exception as e:
            self.logger.error(f"Failed to fetch match {match_url}: {e}")
            self.log_scrape(self.get_source_name(), match_url, 500, "failed", error=str(e))
            return None
