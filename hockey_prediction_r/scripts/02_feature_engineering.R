# scripts/02_feature_engineering.R

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(lubridate)
  library(stringr)
})

cat("========================================\n")
cat("RUNNING FEATURE ENGINEERING\n")
cat("========================================\n")

file_path <- "data/hockey_matches_final_enriched.xlsx"
df <- read_excel(file_path, sheet = 1)

# Ensure date format and chronological sorting
df$match_date <- as.Date(df$match_date)
df <- df %>% arrange(match_date)

# ELO Parameters
K <- 20
INITIAL_ELO <- 1500

# Initialize team stats tracking
team_stats <- list()
h2h_stats <- list()
team_elo <- list()

get_team_elo <- function(team) {
  if (is.null(team_elo[[team]])) return(INITIAL_ELO)
  return(team_elo[[team]])
}

update_elo <- function(team_a, team_b, score_a, score_b) {
  Ra <- get_team_elo(team_a)
  Rb <- get_team_elo(team_b)
  
  Ea <- 1 / (1 + 10^((Rb - Ra) / 400))
  Eb <- 1 / (1 + 10^((Ra - Rb) / 400))
  
  Sa <- if (score_a > score_b) 1 else if (score_a == score_b) 0.5 else 0
  Sb <- if (score_b > score_a) 1 else if (score_a == score_b) 0.5 else 0
  
  # Margin of victory multiplier
  mov <- abs(score_a - score_b)
  mult <- log(mov + 1)
  if (mov == 0) mult <- 1
  
  Ra_new <- Ra + K * mult * (Sa - Ea)
  Rb_new <- Rb + K * mult * (Sb - Eb)
  
  team_elo[[team_a]] <<- Ra_new
  team_elo[[team_b]] <<- Rb_new
}

# Add columns for features
features <- list()

for (i in 1:nrow(df)) {
  row <- df[i, ]
  ta <- row$team_a
  tb <- row$team_b
  
  # Initialize stats if not exist
  if (is.null(team_stats[[ta]])) {
    team_stats[[ta]] <- list(matches = 0, wins = 0, goals_scored = 0, goals_conceded = 0, 
                             history = character(), goal_diff_history = numeric())
  }
  if (is.null(team_stats[[tb]])) {
    team_stats[[tb]] <- list(matches = 0, wins = 0, goals_scored = 0, goals_conceded = 0, 
                             history = character(), goal_diff_history = numeric())
  }
  
  h2h_key <- paste(sort(c(ta, tb)), collapse = "_")
  if (is.null(h2h_stats[[h2h_key]])) {
    h2h_stats[[h2h_key]] <- list(matches = 0, wins = list())
  }
  
  # 1. CALCULATE FEATURES (strictly before current match)
  sa <- team_stats[[ta]]
  sb <- team_stats[[tb]]
  h2h <- h2h_stats[[h2h_key]]
  
  feat <- list()
  
  # ELO
  feat$team_a_elo <- get_team_elo(ta)
  feat$team_b_elo <- get_team_elo(tb)
  feat$elo_difference <- feat$team_a_elo - feat$team_b_elo
  
  # Matches played
  feat$team_a_matches <- sa$matches
  feat$team_b_matches <- sb$matches
  
  # Win rate
  feat$team_a_win_rate <- ifelse(sa$matches > 0, sa$wins / sa$matches, NA)
  feat$team_b_win_rate <- ifelse(sb$matches > 0, sb$wins / sb$matches, NA)
  
  # Recent form (last 5, 10)
  feat$team_a_form_5 <- ifelse(length(sa$history) > 0, sum(tail(sa$history, 5) == "W") / min(5, length(sa$history)), NA)
  feat$team_b_form_5 <- ifelse(length(sb$history) > 0, sum(tail(sb$history, 5) == "W") / min(5, length(sb$history)), NA)
  feat$team_a_form_10 <- ifelse(length(sa$history) > 0, sum(tail(sa$history, 10) == "W") / min(10, length(sa$history)), NA)
  feat$team_b_form_10 <- ifelse(length(sb$history) > 0, sum(tail(sb$history, 10) == "W") / min(10, length(sb$history)), NA)
  
  # Goals
  feat$team_a_avg_scored <- ifelse(sa$matches > 0, sa$goals_scored / sa$matches, NA)
  feat$team_b_avg_scored <- ifelse(sb$matches > 0, sb$goals_scored / sb$matches, NA)
  feat$team_a_avg_conceded <- ifelse(sa$matches > 0, sa$goals_conceded / sa$matches, NA)
  feat$team_b_avg_conceded <- ifelse(sb$matches > 0, sb$goals_conceded / sb$matches, NA)
  
  # Goal diff
  feat$team_a_avg_gd <- feat$team_a_avg_scored - feat$team_a_avg_conceded
  feat$team_b_avg_gd <- feat$team_b_avg_scored - feat$team_b_avg_conceded
  
  feat$team_a_recent_gd <- ifelse(length(sa$goal_diff_history) > 0, mean(tail(sa$goal_diff_history, 5)), NA)
  feat$team_b_recent_gd <- ifelse(length(sb$goal_diff_history) > 0, mean(tail(sb$goal_diff_history, 5)), NA)
  
  # Head-to-Head
  feat$h2h_matches <- h2h$matches
  ta_h2h_wins <- if(is.null(h2h$wins[[ta]])) 0 else h2h$wins[[ta]]
  feat$team_a_h2h_win_rate <- ifelse(h2h$matches > 0, ta_h2h_wins / h2h$matches, NA)
  
  # Save features
  features[[i]] <- feat
  
  # 2. UPDATE STATE (after calculating features)
  if (!is.na(row$team_a_score) && !is.na(row$team_b_score)) {
    # Update ELO
    update_elo(ta, tb, row$team_a_score, row$team_b_score)
    
    # Update stats A
    team_stats[[ta]]$matches <- team_stats[[ta]]$matches + 1
    team_stats[[ta]]$goals_scored <- team_stats[[ta]]$goals_scored + row$team_a_score
    team_stats[[ta]]$goals_conceded <- team_stats[[ta]]$goals_conceded + row$team_b_score
    team_stats[[ta]]$goal_diff_history <- c(team_stats[[ta]]$goal_diff_history, row$team_a_score - row$team_b_score)
    
    res_a <- if(row$team_a_score > row$team_b_score) "W" else if(row$team_a_score < row$team_b_score) "L" else "D"
    if (row$result != "DRAW" && row$team_a_score == row$team_b_score) {
       res_a <- if (row$winner == ta) "W" else "L"
    }
    team_stats[[ta]]$history <- c(team_stats[[ta]]$history, res_a)
    if(res_a == "W") team_stats[[ta]]$wins <- team_stats[[ta]]$wins + 1
    
    # Update stats B
    team_stats[[tb]]$matches <- team_stats[[tb]]$matches + 1
    team_stats[[tb]]$goals_scored <- team_stats[[tb]]$goals_scored + row$team_b_score
    team_stats[[tb]]$goals_conceded <- team_stats[[tb]]$goals_conceded + row$team_a_score
    team_stats[[tb]]$goal_diff_history <- c(team_stats[[tb]]$goal_diff_history, row$team_b_score - row$team_a_score)
    
    res_b <- if(row$team_b_score > row$team_a_score) "W" else if(row$team_b_score < row$team_a_score) "L" else "D"
    if (row$result != "DRAW" && row$team_a_score == row$team_b_score) {
       res_b <- if (row$winner == tb) "W" else "L"
    }
    team_stats[[tb]]$history <- c(team_stats[[tb]]$history, res_b)
    if(res_b == "W") team_stats[[tb]]$wins <- team_stats[[tb]]$wins + 1
    
    # Update H2H
    h2h_stats[[h2h_key]]$matches <- h2h_stats[[h2h_key]]$matches + 1
    if (res_a == "W") {
      if(is.null(h2h_stats[[h2h_key]]$wins[[ta]])) h2h_stats[[h2h_key]]$wins[[ta]] <- 0
      h2h_stats[[h2h_key]]$wins[[ta]] <- h2h_stats[[h2h_key]]$wins[[ta]] + 1
    } else if (res_b == "W") {
      if(is.null(h2h_stats[[h2h_key]]$wins[[tb]])) h2h_stats[[h2h_key]]$wins[[tb]] <- 0
      h2h_stats[[h2h_key]]$wins[[tb]] <- h2h_stats[[h2h_key]]$wins[[tb]] + 1
    }
  }
}

# Bind features to df
feat_df <- bind_rows(features)
df <- bind_cols(df, feat_df)

# Create Target
df$team_a_win_binary <- ifelse(!is.na(df$winner) & df$winner == df$team_a, 1, 0)

# Save intermediate feature engineered dataset securely
saveRDS(df, "data/hockey_matches_features.rds")
cat(sprintf("Feature engineering complete. Saved to data/hockey_matches_features.rds\n"))
