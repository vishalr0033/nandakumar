# scripts/predict_match.R

suppressPackageStartupMessages({
  library(dplyr)
  library(xgboost)
  library(ranger)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) >= 3) {
  team_a <- args[1]
  team_b <- args[2]
m_date <- as.Date(args[3])
} else {
  team_a <- "India"
  team_b <- "Australia"
  m_date <- Sys.Date()
}

df <- readRDS("data/hockey_matches_features.rds")

# Ensure df is ordered
df <- df %>% arrange(match_date) %>% filter(match_date < m_date)

get_last_stats <- function(team) {
  # Find last match where team played
  last_a <- df %>% filter(team_a == team) %>% tail(1)
  last_b <- df %>% filter(team_b == team) %>% tail(1)
  
  # Determine which is the absolute latest
  if (nrow(last_a) == 0 && nrow(last_b) == 0) return(NULL)
  
  if (nrow(last_a) > 0 && nrow(last_b) > 0) {
    if (last_a$match_date > last_b$match_date) {
      last <- last_a
      role <- "A"
    } else {
      last <- last_b
      role <- "B"
    }
  } else if (nrow(last_a) > 0) {
    last <- last_a
    role <- "A"
  } else {
    last <- last_b
    role <- "B"
  }
  
  if (role == "A") {
    # It hasn't updated AFTER this match yet in the dataset, wait, the dataset features are BEFORE the match!
    # To get stats BEFORE a FUTURE match, we need the stats AFTER their last match.
    # But our dataset only stores stats BEFORE the match.
    # We'd have to calculate the post-match state.
    # Simplification for prediction function: Just use their stats going INTO their last match as an approximation,
    # OR we can just query the last row and we know that's quite close. 
    # Actually, ELO diff and recent form are the most important.
    
    # Let's extract the stats as they were recorded in the dataset
    return(list(
      elo = last$team_a_elo,
      win_rate = last$team_a_win_rate,
      form_5 = last$team_a_form_5,
      form_10 = last$team_a_form_10,
      avg_gd = last$team_a_avg_gd,
      recent_gd = last$team_a_recent_gd,
      matches = last$team_a_matches
    ))
  } else {
    return(list(
      elo = last$team_b_elo,
      win_rate = last$team_b_win_rate,
      form_5 = last$team_b_form_5,
      form_10 = last$team_b_form_10,
      avg_gd = last$team_b_avg_gd,
      recent_gd = last$team_b_recent_gd,
      matches = last$team_b_matches
    ))
  }
}

stats_a <- get_last_stats(team_a)
stats_b <- get_last_stats(team_b)

if (is.null(stats_a) || is.null(stats_b)) {
  stop("Insufficient historical data for one or both teams prior to this date.")
}

# H2H
h2h_matches <- df %>% filter((team_a == team_a & team_b == team_b) | (team_a == team_b & team_b == team_a)) %>% tail(1)
if (nrow(h2h_matches) > 0) {
  if (h2h_matches$team_a == team_a) {
    h2h_wr <- h2h_matches$team_a_h2h_win_rate
  } else {
    # Invert
    h2h_wr <- if(is.na(h2h_matches$team_a_h2h_win_rate)) NA else 1 - h2h_matches$team_a_h2h_win_rate
  }
  h2h_count <- h2h_matches$h2h_matches
} else {
  h2h_wr <- 0.5
  h2h_count <- 0
}

# Build feature row
feat_row <- data.frame(
  elo_difference = stats_a$elo - stats_b$elo,
  team_a_elo = stats_a$elo,
  team_b_elo = stats_b$elo,
  team_a_win_rate = stats_a$win_rate,
  team_b_win_rate = stats_b$win_rate,
  team_a_form_5 = stats_a$form_5,
  team_b_form_5 = stats_b$form_5,
  team_a_form_10 = stats_a$form_10,
  team_b_form_10 = stats_b$form_10,
  team_a_avg_gd = stats_a$avg_gd,
  team_b_avg_gd = stats_b$avg_gd,
  team_a_recent_gd = stats_a$recent_gd,
  team_b_recent_gd = stats_b$recent_gd,
  team_a_h2h_win_rate = h2h_wr,
  team_a_matches = stats_a$matches,
  team_b_matches = stats_b$matches,
  h2h_matches = h2h_count
)

# Impute NA
for(col in names(feat_row)) {
  feat_row[[col]][is.na(feat_row[[col]])] <- 0
}

# Load model
model <- readRDS("models/hockey_winner_model.rds")
meta <- jsonlite::read_json("models/model_metadata.json")

# Predict
if (meta$model_type == "XGBoost") {
  dtest <- xgb.DMatrix(as.matrix(feat_row))
  prob_a <- predict(model, dtest)
} else if (meta$model_type == "Random Forest (ranger)") {
  prob_a <- predict(model, data = feat_row)$predictions[, "Win"]
} else {
  prob_a <- predict(model, newdata = feat_row, type = "response")
}

prob_a_pct <- prob_a * 100
prob_b_pct <- (1 - prob_a) * 100

predicted_winner <- if (prob_a > 0.5) team_a else team_b

confidence <- if (abs(prob_a - 0.5) > 0.3) "HIGH" else if (abs(prob_a - 0.5) > 0.15) "MEDIUM" else "LOW"

cat("\n====================================\n")
cat("PREDICTION OUTCOME\n")
cat("====================================\n")
cat(sprintf("%s: %.1f%%\n", team_a, prob_a_pct))
cat(sprintf("%s: %.1f%%\n", team_b, prob_b_pct))
cat("\n")
cat(sprintf("Predicted winner: %s\n", predicted_winner))
cat(sprintf("Confidence: %s\n", confidence))
cat("====================================\n")
cat("EXPLANATION / EVIDENCE\n")
cat("====================================\n")

if (stats_a$elo > stats_b$elo) {
  cat(sprintf("+ %s has a higher ELO rating (%.0f vs %.0f)\n", team_a, stats_a$elo, stats_b$elo))
} else {
  cat(sprintf("- %s has a lower ELO rating (%.0f vs %.0f)\n", team_a, stats_a$elo, stats_b$elo))
}

if (stats_a$form_5 > stats_b$form_5) {
  cat(sprintf("+ %s has better recent form (%.0f%% vs %.0f%% win rate in last 5)\n", team_a, stats_a$form_5*100, stats_b$form_5*100))
} else {
  cat(sprintf("- %s has worse recent form (%.0f%% vs %.0f%% win rate in last 5)\n", team_a, stats_a$form_5*100, stats_b$form_5*100))
}

if (stats_a$avg_gd > stats_b$avg_gd) {
  cat(sprintf("+ %s has a better average goal difference (%.2f vs %.2f)\n", team_a, stats_a$avg_gd, stats_b$avg_gd))
} else {
  cat(sprintf("- %s has a worse average goal difference (%.2f vs %.2f)\n", team_a, stats_a$avg_gd, stats_b$avg_gd))
}

if (h2h_count > 0) {
  if (h2h_wr > 0.5) {
    cat(sprintf("+ %s historically dominates the Head-to-Head matchup (%.0f%% win rate over %d matches)\n", team_a, h2h_wr*100, h2h_count))
  } else if (h2h_wr < 0.5) {
    cat(sprintf("- %s historically struggles in the Head-to-Head matchup (%.0f%% win rate over %d matches)\n", team_a, h2h_wr*100, h2h_count))
  } else {
    cat(sprintf("= Head-to-Head is perfectly balanced (50%% over %d matches)\n", h2h_count))
  }
} else {
  cat("= No previous Head-to-Head matches recorded before this date.\n")
}
