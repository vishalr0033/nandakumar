import pandas as pd
from hockey_data_collection import config

class ExcelExporter:
    def export(self, matches):
        df = pd.DataFrame(matches)
        
        # Save CSV
        df.to_csv(config.RAW_MATCHES_CSV, index=False)
        
        # Save Excel with sheets
        with pd.ExcelWriter(config.RAW_MATCHES_EXCEL, engine='openpyxl') as writer:
            df.to_excel(writer, sheet_name='matches', index=False)
            
            # team_mapping
            if config.TEAM_MAPPING_CSV.exists():
                pd.read_csv(config.TEAM_MAPPING_CSV).to_excel(writer, sheet_name='team_mapping', index=False)
            else:
                pd.DataFrame(columns=['raw_name', 'standard_name']).to_excel(writer, sheet_name='team_mapping', index=False)
                
            # source_summary
            if config.SCRAPING_LOG_CSV.exists():
                pd.read_csv(config.SCRAPING_LOG_CSV).to_excel(writer, sheet_name='scraping_log', index=False)
