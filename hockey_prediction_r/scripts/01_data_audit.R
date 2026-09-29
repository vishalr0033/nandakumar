# scripts/01_data_audit.R

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(lubridate)
  library(stringr)
})

cat("========================================\n")
cat("RUNNING DATA AUDIT\n")
cat("========================================\n")

# Load data
file_path <- "data/hockey_matches_final_enriched.xlsx"
if (!file.exists(file_path)) {
  stop(sprintf("ERROR: Dataset not found at %s", file_path))
}

# The dataset is on the first sheet
df <- read_excel(file_path, sheet = 1)

# Open report connection
report_file <- "reports/data_audit.txt"
sink(report_file)

cat("====================================\n")
cat("DATA AUDIT REPORT\n")
cat("====================================\n\n")

# Basic counts
cat(sprintf("Row count: %d\n", nrow(df)))
cat(sprintf("Column count: %d\n", ncol(df)))

# Duplicates
dup_ids <- sum(duplicated(df$match_id))
dup_rows <- sum(duplicated(df))
cat(sprintf("Duplicate match IDs: %d\n", dup_ids))
cat(sprintf("Duplicate rows: %d\n", dup_rows))

# Missing values summary
cat("\nMissing values per column:\n")
missing_counts <- sapply(df, function(x) sum(is.na(x)))
for (col in names(missing_counts)) {
  if (missing_counts[col] > 0) {
    cat(sprintf("  %s: %d\n", col, missing_counts[col]))
  }
}

# Invalid dates
if ("match_date" %in% names(df)) {
  invalid_dates <- sum(is.na(as.Date(df$match_date)))
  cat(sprintf("\nInvalid dates: %d\n", invalid_dates))
  
  # Future matches
  future_matches <- sum(as.Date(df$match_date) > Sys.Date(), na.rm = TRUE)
  cat(sprintf("Future matches: %d\n", future_matches))
}

# Scores validation
invalid_scores <- sum(df$team_a_score < 0 | df$team_b_score < 0, na.rm = TRUE)
cat(sprintf("Invalid scores (negative): %d\n", invalid_scores))

# Winner consistency
invalid_winners <- 0
for (i in 1:nrow(df)) {
  row <- df[i, ]
  if (!is.na(row$team_a_score) && !is.na(row$team_b_score)) {
    calc_winner <- if (row$team_a_score > row$team_b_score) {
      row$team_a
    } else if (row$team_b_score > row$team_a_score) {
      row$team_b
    } else {
      "DRAW"
    }
    
    if (row$result != "DRAW") {
       if (calc_winner != "DRAW" && calc_winner != row$winner) {
          # Handle shootout wins where score might be tied but there is a winner
          # If score isn't tied, and winner doesn't match highest score, it's inconsistent
          if (row$team_a_score != row$team_b_score) {
             invalid_winners <- invalid_winners + 1
          }
       }
    }
  }
}
cat(sprintf("Inconsistent winners (excluding shootouts): %d\n", invalid_winners))

sink()
cat(sprintf("Audit complete. Report saved to %s\n", report_file))
