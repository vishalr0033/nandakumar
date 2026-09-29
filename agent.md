PROJECT: 2026 MEN'S FIH HOCKEY WORLD CUP PREDICTION
STEP 1 ONLY: HISTORICAL DATA COLLECTION

I am building a machine-learning project to predict the winner of men's field hockey matches, with the final goal of predicting matches in the 2026 Men's FIH Hockey World Cup.

YOUR CURRENT TASK IS ONLY:

COLLECT REAL HISTORICAL HOCKEY MATCH DATA FROM PUBLIC WEB SOURCES.

DO NOT:
- train any ML model
- perform prediction
- perform feature engineering
- create synthetic/fake data
- generate random values
- guess missing values
- build an R model
- calculate future-match features

The output of this step will later be used for data cleaning, feature engineering and ML training in R.

==================================================
1. MAIN DATA COLLECTION TARGET
==================================================

Collect at least:

MINIMUM: 1,000 UNIQUE REAL MATCHES

Preferred target:

1,500–3,000+ UNIQUE REAL MATCHES

Collect men's senior international OUTDOOR field hockey matches.

Prefer historical matches from approximately 2010–2026.

If required to reach 1,000 high-quality matches, extend the historical period further.

DO NOT collect:
- women's hockey
- junior hockey
- youth hockey
- indoor hockey
- club-only matches
- fictional/generated matches
- duplicate matches

==================================================
2. DATA SOURCE STRATEGY
==================================================

First identify reliable public sources.

Priority:

1. FIH / International Hockey Federation
2. Official tournament websites
3. Official national hockey federation websites
4. Reliable public hockey databases
5. Reliable sports-result websites

Search for historical match results from:

- FIH Hockey World Cup
- FIH Hockey Pro League
- Olympic Games
- Commonwealth Games
- Asian Games
- Asian Champions Trophy
- EuroHockey
- Nations Cup
- Hockey World League
- Continental championships
- Other recognized senior men's international competitions

IMPORTANT:

Do not scrape blindly.

First inspect candidate websites and determine:
- whether historical matches are available
- number of matches
- available fields
- page structure
- whether pages are static or JavaScript
- whether automated access is allowed
- whether robots.txt restricts crawling

Create:

data_source_report.md

with:

source_name
source_url
data_available
years_available
estimated_match_count
available_columns
scraping_method
reliability
robots_status
notes

Use the best available legitimate sources.

If one source cannot provide 1,000+ matches, use multiple legitimate sources.

==================================================
3. LEGAL AND SAFE SCRAPING
==================================================

Respect:
- robots.txt
- Terms of Service
- reasonable request rates
- website restrictions

DO NOT:
- bypass CAPTCHA
- bypass login
- bypass authentication
- bypass anti-bot systems
- rotate IPs to evade blocking
- use stolen API keys
- bypass paywalls

If a website blocks automated scraping:

STOP using that source and use another legitimate public source.

Use polite request delays.

Default request delay:

1–3 seconds where appropriate.

Use sequential requests.

Do not aggressively parallelize requests.

==================================================
4. REQUIRED RAW DATA COLUMNS
==================================================

Create ONE ROW PER MATCH.

Collect the following fields whenever the source provides them.

-----------------------------
MATCH IDENTITY
-----------------------------

match_id
match_date
match_time
year
season

-----------------------------
COMPETITION
-----------------------------

tournament
tournament_type
tournament_level
match_stage
pool_group
match_number

-----------------------------
TEAMS
-----------------------------

team_a
team_b
team_a_code
team_b_code

-----------------------------
RESULT
-----------------------------

team_a_score
team_b_score

winner
loser
result

goal_difference

decision_method

Possible decision_method values:

REGULATION
EXTRA_TIME
SHOOTOUT
UNKNOWN

-----------------------------
LOCATION
-----------------------------

venue
city
country

neutral_venue

-----------------------------
MATCH PERFORMANCE
-----------------------------

team_a_goals
team_b_goals

team_a_penalty_corners
team_b_penalty_corners

team_a_shots
team_b_shots

team_a_possession
team_b_possession

-----------------------------
DISCIPLINE
-----------------------------

team_a_green_cards
team_b_green_cards

team_a_yellow_cards
team_b_yellow_cards

team_a_red_cards
team_b_red_cards

-----------------------------
GOAL TIMING
-----------------------------

team_a_q1_goals
team_a_q2_goals
team_a_q3_goals
team_a_q4_goals

team_b_q1_goals
team_b_q2_goals
team_b_q3_goals
team_b_q4_goals

-----------------------------
RANKING INFORMATION
-----------------------------

team_a_world_rank
team_b_world_rank

ranking_date

IMPORTANT:

Only collect ranking values if they are actually available from the source and can be associated with the match date.

Do not use a ranking published AFTER the match.

If historical ranking information is unavailable:

leave blank.

-----------------------------
TOURNAMENT CONTEXT
-----------------------------

team_a_pool_position
team_b_pool_position

team_a_tournament_points
team_b_tournament_points

Only collect these if the source provides them.

-----------------------------
SOURCE / PROVENANCE
-----------------------------

source_name
source_url
source_match_url

scraped_at

==================================================
5. MISSING DATA RULE
==================================================

THIS IS EXTREMELY IMPORTANT.

If the website does not provide a field:

LEAVE IT BLANK / NULL.

NEVER:
- guess
- estimate
- generate
- interpolate
- use random values
- copy values from another match

Example:

If penalty corners are unavailable:

team_a_penalty_corners = NULL
team_b_penalty_corners = NULL

If shots are unavailable:

team_a_shots = NULL
team_b_shots = NULL

The dataset must contain ONLY REAL INFORMATION.

==================================================
6. SCORE AND RESULT RULES
==================================================

If:

team_a_score > team_b_score

then:

winner = team_a
loser = team_b
result = A_WIN

If:

team_b_score > team_a_score

then:

winner = team_b
loser = team_a
result = B_WIN

If:

team_a_score == team_b_score

then:

result = DRAW

Do not assign a winner to a regulation-time draw.

For matches decided by shootout:

preserve the regulation score separately if available.

Store:

decision_method = SHOOTOUT

If the source gives the final winner, store the winner separately.

Do not incorrectly convert shootout results into normal regulation scores.

==================================================
7. TEAM NAME STANDARDIZATION
==================================================

Different websites may use different names.

Create:

team_name_mapping.csv

Example:

raw_name,standard_name

India Men,India
India,India
IND,India

Australia Men,Australia
Australia,Australia
AUS,Australia

Netherlands Men,Netherlands

Standardize team names carefully.

DO NOT accidentally merge different teams.

Keep the original raw team name internally for traceability.

==================================================
8. MATCH ID
==================================================

Create a deterministic unique match_id.

Use a combination of:

match_date
team_a
team_b
tournament

Example:

2018-12-05_India_Australia_HockeyWorldCup

Normalize the values so the ID is stable.

==================================================
9. DUPLICATE DETECTION
==================================================

Duplicate matches are NOT allowed in the final dataset.

Detect duplicates using:

date
team_a
team_b
tournament

Also detect reversed teams.

Example:

India vs Australia

and

Australia vs India

on the same date and same tournament

may be the same match.

Create:

duplicate_report.csv

with:

duplicate_group
record_1
record_2
duplicate_reason
selected_record

When two sources contain the same match:

merge them.

Prefer the more reliable source.

Do not count the same match twice.

==================================================
10. MULTI-SOURCE DATA MERGING
==================================================

If multiple websites are required:

Keep provenance for every record.

Create:

source_priority

Example:

1 = official FIH
2 = official tournament source
3 = reliable secondary source

If sources disagree:

- compare the original pages
- prefer the most authoritative source
- do not silently overwrite conflicting values
- log conflicts

Create:

data_conflicts.csv

Columns:

match_id
field
source_1_value
source_2_value
selected_value
reason

==================================================
11. DATA VALIDATION
==================================================

Create automated validation.

Check:

- valid date
- valid teams
- team_a != team_b
- valid scores
- scores >= 0
- winner matches score
- loser matches score
- result matches score
- unique match_id
- valid tournament
- valid source URL
- no duplicate match
- men's senior match
- outdoor field hockey
- no impossible dates

Generate:

validation_report.txt

Include:

total_scraped_records
unique_matches
duplicates
invalid_records
unique_teams
unique_tournaments
earliest_match_date
latest_match_date
missing_values_by_column

==================================================
12. DATASET FILES
==================================================

Create these output files:

data/raw_matches.csv

data/raw_matches.xlsx

data/team_name_mapping.csv

data/duplicate_report.csv

data/data_conflicts.csv

data/scraping_log.csv

data/validation_report.txt

data_source_report.md

==================================================
13. EXCEL STRUCTURE
==================================================

raw_matches.xlsx must contain these sheets:

Sheet 1:
matches

Sheet 2:
team_mapping

Sheet 3:
source_summary

Sheet 4:
validation_report

Sheet 5:
scraping_log

Format the Excel file professionally:

- freeze header row
- enable filters
- readable column widths
- proper date formatting
- blank cells for missing values
- no Python objects
- one match per row

==================================================
14. SCRAPING LOG
==================================================

Create:

scraping_log.csv

Columns:

timestamp
source_name
url
http_status
status
records_found
records_added
duplicates_found
error_message

==================================================
15. RESUMABLE SCRAPING
==================================================

The scraper must be resumable.

If the process stops after collecting 600 matches, restarting it must NOT begin from zero.

Create:

checkpoint.json

Store:

last_processed_url
last_processed_page
records_collected
timestamp

Save progress regularly.

==================================================
16. REQUEST HANDLING
==================================================

Use Python requests or httpx.

Use:

- timeout
- retries
- exponential backoff
- User-Agent
- reasonable delay
- exception handling

Handle:

HTTP 403
HTTP 404
HTTP 429
HTTP 500
HTTP 502
HTTP 503
connection timeout
network failure

For HTTP 429:

respect Retry-After if available.

Do not bypass rate limiting.

==================================================
17. PYTHON ENVIRONMENT
==================================================

Create a virtual environment.

Use:

python -m venv .venv

Windows:

.venv\Scripts\activate

Create:

requirements.txt

Use lightweight packages only.

Preferred:

requests
httpx
beautifulsoup4
lxml
pandas
openpyxl
python-dateutil
tqdm
tenacity
urllib3

Only install additional packages when technically necessary.

Do NOT install:

TensorFlow
PyTorch
CUDA
large ML libraries
unnecessary GPU libraries

This phase is ONLY data collection.

==================================================
18. PROJECT STRUCTURE
==================================================

Create:

hockey_data_collection/

    main.py
    config.py
    requirements.txt
    README.md
    data_source_report.md

    scrapers/
        __init__.py
        base_scraper.py
        fih_scraper.py
        secondary_scraper.py

    parsers/
        __init__.py
        match_parser.py
        team_parser.py

    processors/
        __init__.py
        cleaner.py
        normalizer.py
        deduplicator.py

    validators/
        __init__.py
        validator.py

    exporters/
        __init__.py
        excel_exporter.py

    data/
        raw_matches.csv
        raw_matches.xlsx
        team_name_mapping.csv
        duplicate_report.csv
        data_conflicts.csv
        scraping_log.csv
        validation_report.txt

    logs/

    tests/
        test_parser.py
        test_normalizer.py
        test_deduplication.py
        test_validator.py

==================================================
19. TEST BEFORE FULL SCRAPE
==================================================

DO NOT immediately scrape thousands of pages.

First run:

python main.py --discover-sources

Then:

python main.py --limit 20

Collect only 20 matches.

Validate:

- team names
- dates
- scores
- tournament
- winner
- source URLs
- duplicates
- Excel export

Fix all problems.

Then run the full scraper.

==================================================
20. COMMANDS
==================================================

Implement:

python main.py --discover-sources

python main.py --limit 20

python main.py --scrape

python main.py --validate

python main.py --export

python main.py --all

==================================================
21. DATA QUALITY TARGET
==================================================

Final target:

Minimum:
1,000 unique real matches

Preferred:
1,500–3,000+ unique real matches

BUT:

Quality is more important than quantity.

If only 900 verified matches are available from one source:

DO NOT fabricate the remaining 100.

Use another legitimate source.

==================================================
22. IMPORTANT: RAW DATA ONLY
==================================================

Do NOT calculate:

recent form
last 5 wins
last 10 wins
win percentage
H2H percentage
rest days
rolling averages
ELO
team strength score
ranking difference
feature importance
prediction probability

These belong to later stages.

This step must preserve the raw historical information.

==================================================
23. PREVENT FUTURE DATA LEAKAGE
==================================================

Although this step does not perform ML:

preserve exact match dates.

Do not replace dates with only years.

Do not overwrite historical ranking dates.

Do not use current rankings for old matches.

Do not add future information to historical records.

The future R feature-engineering stage will use chronological data.

==================================================
24. FINAL REPORT
==================================================

After completion generate:

FINAL_DATA_COLLECTION_REPORT.md

Include:

Total scraped records:
Unique matches:
Duplicates removed:
Invalid records:
Number of teams:
Number of tournaments:
Earliest match:
Latest match:

Matches by year:
Matches by tournament:
Matches by team:

Missing data percentage:

Column | Missing %

Sources used:

Source | Records | Unique matches

Data conflicts:

Number of conflicts

Validation:

Passed:
Failed:

==================================================
25. FINAL TERMINAL OUTPUT
==================================================

At the end print:

========================================
HOCKEY HISTORICAL DATA COLLECTION
========================================

Target:
1000+ unique matches

Collected:
XXXX

Unique:
XXXX

Duplicates removed:
XXXX

Invalid:
XXXX

Teams:
XX

Tournaments:
XX

Date range:
YYYY-MM-DD → YYYY-MM-DD

========================================

FILES CREATED:

raw_matches.xlsx
raw_matches.csv
team_name_mapping.csv
duplicate_report.csv
data_conflicts.csv
scraping_log.csv
validation_report.txt
FINAL_DATA_COLLECTION_REPORT.md

========================================

IMPORTANT:
Do not proceed to ML training or prediction.

STOP after successful Step 1 data collection.

The next phase will be done separately in R:
DATA CLEANING → FEATURE ENGINEERING → TRAIN/TEST SPLIT → ML TRAINING → MODEL EVALUATION → 2026 MATCH PREDICTION.