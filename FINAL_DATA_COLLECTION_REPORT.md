# Men's International Hockey Match Prediction: Data Collection Report

## Executive Summary

This report concludes the **Data Collection & Preparation** phase for the historical Men's International Hockey dataset.
The goal was to acquire 1,000+ matches to be used later in R for Machine Learning.

Through automated discovery and concurrent scraping of the FIH Tournament Management System (TMS), we have successfully extracted a massive dataset spanning 14 years of historical matches, vastly outperforming the initial target.

## Final Dataset Statistics

- **Target Size:** 1,000 matches
- **Final Dataset Size:** **7,120 matches**
- **Data Period:** 2012 - 2026
- **Total Competitions Audited:** 617 unique Senior Men's Outdoor tournaments.
- **Export Formats:** Both `.xlsx` (Excel) and `.csv` formats have been generated.

## Data Quality & Integrity

As per strict requirements:

1. **No ML trained:** The pipeline is exclusively a data pipeline.
2. **No Data Fabrication:** Missing metrics (e.g., if FIH did not record the number of penalty corners for a 2013 match) were explicitly left blank. 494 matches had missing score data, but they were kept in their raw state.
3. **No Synthetic Data:** All rows directly reflect actual DOM nodes found on `tms.fih.ch`.
4. **Team Normalization:** Applied via `team_mapping.csv` to ensure standard country names.
5. **No R Used:** The entire suite was executed in Python.

## Deliverables

The following files are now available in your `data/` directory:

| File                          | Description                                                    |
| ----------------------------- | -------------------------------------------------------------- |
| `hockey_matches_final.xlsx` | The primary dataset containing all 7,120 records (Excel).      |
| `hockey_matches_final.csv`  | The primary dataset containing all 7,120 records (CSV).        |
| `team_mapping.csv`          | The mapping dictionary used to standardize country/team names. |

## Next Steps for the USER

You are now ready to begin the Machine Learning phase! You can safely import `hockey_matches_final.csv` into your R environment and begin feature engineering, probability calculations, and model training.
