# app/app.R
# ==============================================================================
# HOCKEY INTELLIGENCE & WORLD CUP 2026 PREDICTION SUITE
# Advanced Machine Learning Analytics, Real-Time Forecasting & Tournament Simulation
# ==============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(plotly)
  library(DT)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(xgboost)
  library(ranger)
  library(htmltools)
  library(scales)
})

# ------------------------------------------------------------------------------
# 1. LOAD DATA & TRAINED V4 ENSEMBLE MODEL (ROBUST PATH LOOKUP)
# ------------------------------------------------------------------------------
find_resource <- function(rel_path) {
  candidates <- c(
    rel_path,
    file.path("..", rel_path),
    file.path("hockey_prediction_r", rel_path),
    file.path("nandhu/hockey_prediction_r", rel_path),
    file.path("c:/Users/rajap/OneDrive/Desktop/r pr/nandhu/hockey_prediction_r", rel_path)
  )
  for (cand in candidates) {
    if (file.exists(cand)) return(normalizePath(cand))
  }
  return(rel_path)
}

model_path <- find_resource("models/hockey_winner_model_v4.rds")
data_path_rds <- find_resource("data/hockey_prediction_dataset_v4.rds")
if (!file.exists(data_path_rds)) {
  data_path_rds <- find_resource("data/hockey_prediction_dataset_v4.xlsx")
}
fixtures_path <- find_resource("data/world_cup_2026_fixtures.csv")

final_model <- readRDS(model_path)

if (grepl("\\.rds$", data_path_rds)) {
  df <- readRDS(data_path_rds)
} else {
  library(readxl)
  df <- read_excel(data_path_rds)
}

df$match_date <- as.Date(df$match_date)
df <- df %>% arrange(match_date)

# ------------------------------------------------------------------------------
# 2. COUNTRY CODE & DISPLAY NAME STANDARDIZATION DICTIONARY
# ------------------------------------------------------------------------------
code_to_display <- c(
  "IND" = "India", "India" = "India",
  "PAK" = "Pakistan", "Pakistan" = "Pakistan",
  "AUS" = "Australia", "Australia" = "Australia",
  "NED" = "Netherlands", "Netherlands" = "Netherlands",
  "BEL" = "Belgium", "Belgium" = "Belgium",
  "GER" = "Germany", "Germany" = "Germany", "FRG" = "Germany", "GDR" = "Germany",
  "ENG" = "England", "England" = "England",
  "ARG" = "Argentina", "Argentina" = "Argentina",
  "ESP" = "Spain", "Spain" = "Spain",
  "NZL" = "New Zealand", "New Zealand" = "New Zealand",
  "FRA" = "France", "France" = "France",
  "MAS" = "Malaysia", "Malaysia" = "Malaysia",
  "RSA" = "South Africa", "South Africa" = "South Africa",
  "IRL" = "Ireland", "Ireland" = "Ireland",
  "JPN" = "Japan", "Japan" = "Japan",
  "KOR" = "Korea", "Korea" = "Korea",
  "WAL" = "Wales", "Wales" = "Wales",
  "CAN" = "Canada", "Canada" = "Canada",
  "SCO" = "Scotland", "Scotland" = "Scotland",
  "CHN" = "China", "China" = "China",
  "AUT" = "Austria", "Austria" = "Austria",
  "POL" = "Poland", "Poland" = "Poland",
  "EGY" = "Egypt", "Egypt" = "Egypt",
  "ITA" = "Italy", "Italy" = "Italy",
  "CHI" = "Chile", "Chile" = "Chile",
  "USA" = "USA", "USA" = "USA",
  "GBR" = "Great Britain", "Great Britain" = "Great Britain",
  "BAN" = "Bangladesh", "Bangladesh" = "Bangladesh",
  "RUS" = "Russia", "Russia" = "Russia", "URS" = "Russia", "CIS" = "Russia",
  "SGP" = "Singapore", "SIN" = "Singapore",
  "GHA" = "Ghana", "KEN" = "Kenya", "OMA" = "Oman",
  "SRI" = "Sri Lanka", "MEX" = "Mexico", "BRA" = "Brazil",
  "CZE" = "Czech Republic", "UKR" = "Ukraine", "SUI" = "Switzerland",
  "BLR" = "Belarus", "CRO" = "Croatia", "THA" = "Thailand",
  "TTO" = "Trinidad & Tobago", "INA" = "Indonesia", "HKG" = "Hong Kong",
  "ZIM" = "Zimbabwe", "NGR" = "Nigeria", "PER" = "Peru",
  "URU" = "Uruguay", "VEN" = "Venezuela", "FIN" = "Finland",
  "LTU" = "Lithuania", "NOR" = "Norway", "SWE" = "Sweden",
  "POR" = "Portugal", "TUR" = "Turkey", "QAT" = "Qatar",
  "KAZ" = "Kazakhstan", "UZB" = "Uzbekistan", "TPE" = "Chinese Taipei",
  "FIJ" = "Fiji", "PNG" = "Papua New Guinea", "VAN" = "Vanuatu",
  "SAM" = "Samoa", "SOL" = "Solomon Islands", "TGA" = "Tonga",
  "GUA" = "Guatemala", "DOM" = "Dominican Rep", "PUR" = "Puerto Rico",
  "BAR" = "Barbados", "JAM" = "Jamaica", "GUY" = "Guyana",
  "BER" = "Bermuda", "PAN" = "Panama", "CRC" = "Costa Rica",
  "BOL" = "Bolivia", "ECU" = "Ecuador", "PAR" = "Paraguay",
  "BOT" = "Botswana", "NAM" = "Namibia", "ZAM" = "Zambia",
  "MAW" = "Malawi", "TAN" = "Tanzania", "UGA" = "Uganda",
  "MAR" = "Morocco", "HUN" = "Hungary", "SVK" = "Slovakia",
  "SLO" = "Slovenia", "BUL" = "Bulgaria", "GRE" = "Greece",
  "CYP" = "Cyprus", "MLT" = "Malta", "GIB" = "Gibraltar",
  "LUX" = "Luxembourg", "AZE" = "Azerbaijan", "DEN" = "Denmark",
  "AFG" = "Afghanistan", "CAM" = "Cambodia", "BRU" = "Brunei",
  "MAC" = "Macau", "MYA" = "Myanmar", "NEP" = "Nepal",
  "KGZ" = "Kyrgyzstan", "TJK" = "Tajikistan", "IRI" = "Iran"
)

# Helper function to get codes for a display name
get_db_aliases <- function(display_name) {
  matched_codes <- names(code_to_display)[code_to_display == display_name]
  unique(c(display_name, matched_codes))
}

# Unique selectable teams with human-friendly full names
available_db_teams <- unique(c(df$team_a, df$team_b))
all_display_names <- unique(unname(sapply(available_db_teams, function(x) {
  if (x %in% names(code_to_display)) code_to_display[[x]] else x
})))

priority_teams <- c("India", "Pakistan", "Australia", "Netherlands", "Belgium", "Germany", 
                    "England", "Argentina", "Spain", "New Zealand", "France", "Malaysia", 
                    "South Africa", "Ireland", "Japan", "Korea", "Wales", "Canada", 
                    "Great Britain", "China", "Poland", "Austria", "Egypt", "Chile", "USA", "Bangladesh")

display_teams_list <- c(intersect(priority_teams, all_display_names), sort(setdiff(all_display_names, priority_teams)))

# ------------------------------------------------------------------------------
# 3. PRECOMPUTE GLOBAL TEAM STATS & ELO RANKINGS
# ------------------------------------------------------------------------------
compute_latest_team_stats <- function() {
  stats_list <- list()
  
  for (disp_name in display_teams_list) {
    aliases <- get_db_aliases(disp_name)
    tm_matches <- df %>% filter(team_a %in% aliases | team_b %in% aliases)
    if (nrow(tm_matches) == 0) next
    
    last_m <- tm_matches %>% slice(n())
    is_a <- (last_m$team_a %in% aliases)
    
    elo_val <- ifelse(is_a, last_m$team_a_elo_k20, last_m$team_b_elo_k20)
    momentum <- ifelse(is_a, last_m$team_a_momentum_win_rate, last_m$team_b_momentum_win_rate)
    ewma_gd <- ifelse(is_a, last_m$team_a_ewma_gd, last_m$team_b_ewma_gd)
    last_date <- last_m$match_date
    
    # Total historical record
    wins <- sum((tm_matches$team_a %in% aliases & tm_matches$winner %in% aliases) | 
                (tm_matches$team_b %in% aliases & tm_matches$winner %in% aliases), na.rm = TRUE)
    draws <- sum(tm_matches$result == "DRAW", na.rm = TRUE)
    losses <- nrow(tm_matches) - wins - draws
    win_pct <- round(wins / nrow(tm_matches) * 100, 1)
    
    # Goals
    gf <- sum(ifelse(tm_matches$team_a %in% aliases, tm_matches$team_a_score, tm_matches$team_b_score), na.rm = TRUE)
    ga <- sum(ifelse(tm_matches$team_a %in% aliases, tm_matches$team_b_score, tm_matches$team_a_score), na.rm = TRUE)
    gf_per_match <- round(gf / nrow(tm_matches), 2)
    ga_per_match <- round(ga / nrow(tm_matches), 2)
    
    # Last 10 matches win rate
    last_10_m <- tail(tm_matches, 10)
    l10_wins <- sum((last_10_m$team_a %in% aliases & last_10_m$winner %in% aliases) | 
                    (last_10_m$team_b %in% aliases & last_10_m$winner %in% aliases), na.rm = TRUE)
    l10_win_rate <- round(l10_wins / nrow(last_10_m) * 100, 1)
    
    continent <- case_when(
      disp_name %in% c("Netherlands", "Belgium", "Germany", "England", "Spain", "France", "Ireland", "Wales", "Scotland", "Austria", "Poland", "Great Britain", "Italy", "Czech Republic") ~ "Europe",
      disp_name %in% c("India", "Pakistan", "Malaysia", "Japan", "Korea", "China", "Bangladesh", "Oman", "Singapore") ~ "Asia",
      disp_name %in% c("Australia", "New Zealand", "Fiji", "Papua New Guinea") ~ "Oceania",
      disp_name %in% c("Argentina", "Chile", "Canada", "USA", "Mexico", "Brazil", "Trinidad & Tobago") ~ "Americas",
      disp_name %in% c("South Africa", "Egypt", "Ghana", "Kenya", "Nigeria") ~ "Africa",
      TRUE ~ "Other"
    )
    
    stats_list[[disp_name]] <- data.frame(
      Team = disp_name,
      Continent = continent,
      ELO = round(elo_val, 1),
      Matches = nrow(tm_matches),
      Wins = wins,
      Draws = draws,
      Losses = losses,
      Win_Pct = win_pct,
      GF_Avg = gf_per_match,
      GA_Avg = ga_per_match,
      GD_Total = gf - ga,
      Form_10 = l10_win_rate,
      Momentum = round(momentum, 3),
      EWMA_GD = round(ewma_gd, 2),
      Last_Match = last_date,
      stringsAsFactors = FALSE
    )
  }
  
  bind_rows(stats_list) %>% arrange(desc(ELO)) %>% mutate(Rank = row_number())
}

global_team_stats <- compute_latest_team_stats()

# ------------------------------------------------------------------------------
# 4. 2026 WORLD CUP OFFICIAL POOLS
# ------------------------------------------------------------------------------
wc_pools <- list(
  "Pool A" = c("Netherlands", "Spain", "Ireland", "Japan"),
  "Pool B" = c("Belgium", "Germany", "France", "Malaysia"),
  "Pool C" = c("Australia", "India", "New Zealand", "South Africa"),
  "Pool D" = c("England", "Argentina", "Korea", "Wales")
)

# ------------------------------------------------------------------------------
# 5. PREDICTION ENGINE CORE FUNCTION (WITH FULL DEFENSIVE GUARDS)
# ------------------------------------------------------------------------------
predict_clash <- function(ta_disp = "India", tb_disp = "Pakistan", m_date = as.Date("2026-08-23")) {
  if (missing(ta_disp) || is.null(ta_disp) || length(ta_disp) == 0 || is.na(ta_disp)) ta_disp <- "India"
  if (missing(tb_disp) || is.null(tb_disp) || length(tb_disp) == 0 || is.na(tb_disp)) tb_disp <- "Pakistan"
  
  if (missing(m_date) || is.null(m_date) || length(m_date) == 0 || is.na(m_date)) {
    m_date <- as.Date("2026-08-23")
  } else {
    m_date <- tryCatch(as.Date(m_date), error = function(e) as.Date("2026-08-23"))
    if (is.na(m_date)) m_date <- as.Date("2026-08-23")
  }
  
  if (ta_disp == tb_disp) {
    alt_teams <- setdiff(display_teams_list, ta_disp)
    tb_disp <- if (length(alt_teams) > 0) alt_teams[1] else "Pakistan"
  }
  
  aliases_a <- get_db_aliases(ta_disp)
  aliases_b <- get_db_aliases(tb_disp)
  
  df_ta <- df %>% filter((team_a %in% aliases_a | team_b %in% aliases_a) & as.Date(match_date) < m_date) %>% arrange(match_date)
  df_tb <- df %>% filter((team_a %in% aliases_b | team_b %in% aliases_b) & as.Date(match_date) < m_date) %>% arrange(match_date)
  
  # Fallback: if no matches prior to date, use all historical matches
  if (nrow(df_ta) == 0) {
    df_ta <- df %>% filter(team_a %in% aliases_a | team_b %in% aliases_a) %>% arrange(match_date)
  }
  if (nrow(df_tb) == 0) {
    df_tb <- df %>% filter(team_a %in% aliases_b | team_b %in% aliases_b) %>% arrange(match_date)
  }
  
  feature_cols <- final_model$feature_cols
  feat_matrix <- data.frame(matrix(0, nrow = 1, ncol = length(feature_cols)))
  colnames(feat_matrix) <- feature_cols
  
  if (nrow(df_ta) > 0) {
    last_ta <- df_ta %>% slice(n())
    for (col in feature_cols) {
      if (startsWith(col, "team_a_")) {
        alt_col <- gsub("team_a_", "team_b_", col)
        val <- ifelse(last_ta$team_a %in% aliases_a, last_ta[[col]], last_ta[[alt_col]])
        if (!is.null(val) && length(val) > 0 && !is.na(val)) feat_matrix[[col]] <- val
      }
    }
  } else {
    feat_matrix$team_a_elo_k20 <- 1450
    feat_matrix$team_a_elo_k10 <- 1450
    feat_matrix$team_a_elo_k30 <- 1450
  }
  
  if (nrow(df_tb) > 0) {
    last_tb <- df_tb %>% slice(n())
    for (col in feature_cols) {
      if (startsWith(col, "team_b_")) {
        alt_col <- gsub("team_b_", "team_a_", col)
        val <- ifelse(last_tb$team_a %in% aliases_b, last_tb[[alt_col]], last_tb[[col]])
        if (!is.null(val) && length(val) > 0 && !is.na(val)) feat_matrix[[col]] <- val
      }
    }
  } else {
    feat_matrix$team_b_elo_k20 <- 1450
    feat_matrix$team_b_elo_k10 <- 1450
    feat_matrix$team_b_elo_k30 <- 1450
  }
  
  feat_matrix$elo_diff_k10 <- feat_matrix$team_a_elo_k10 - feat_matrix$team_b_elo_k10
  feat_matrix$elo_diff_k20 <- feat_matrix$team_a_elo_k20 - feat_matrix$team_b_elo_k20
  feat_matrix$elo_diff_k30 <- feat_matrix$team_a_elo_k30 - feat_matrix$team_b_elo_k30
  feat_matrix$elo_ratio_k20 <- feat_matrix$team_a_elo_k20 / ifelse(feat_matrix$team_b_elo_k20 > 0, feat_matrix$team_b_elo_k20, 1)
  feat_matrix$exp_diff <- feat_matrix$team_a_matches_before - feat_matrix$team_b_matches_before
  
  if (nrow(df_ta) > 0 && !is.null(m_date)) {
    feat_matrix$team_a_rest_days <- as.numeric(m_date - as.Date(last_ta$match_date))
  } else {
    feat_matrix$team_a_rest_days <- 7
  }
  
  if (nrow(df_tb) > 0 && !is.null(m_date)) {
    feat_matrix$team_b_rest_days <- as.numeric(m_date - as.Date(last_tb$match_date))
  } else {
    feat_matrix$team_b_rest_days <- 7
  }
  
  feat_matrix$rest_days_diff <- feat_matrix$team_a_rest_days - feat_matrix$team_b_rest_days
  feat_matrix$team_a_matches_last_7d <- ifelse(feat_matrix$team_a_rest_days <= 7, 1, 0)
  feat_matrix$team_b_matches_last_7d <- ifelse(feat_matrix$team_b_rest_days <= 7, 1, 0)
  feat_matrix$team_a_matches_last_14d <- ifelse(feat_matrix$team_a_rest_days <= 14, 2, 0)
  feat_matrix$team_b_matches_last_14d <- ifelse(feat_matrix$team_b_rest_days <= 14, 2, 0)
  feat_matrix$team_a_matches_last_30d <- ifelse(feat_matrix$team_a_rest_days <= 30, 4, 0)
  feat_matrix$team_b_matches_last_30d <- ifelse(feat_matrix$team_b_rest_days <= 30, 4, 0)
  
  df_h2h <- df %>% filter(((team_a %in% aliases_a & team_b %in% aliases_b) | 
                           (team_a %in% aliases_b & team_b %in% aliases_a))) %>% arrange(match_date)
  
  if (nrow(df_h2h) > 0) {
    last_h2h <- df_h2h %>% slice(n())
    feat_matrix$h2h_matches_before <- nrow(df_h2h)
    
    ta_wins <- sum((df_h2h$team_a %in% aliases_a & df_h2h$winner %in% aliases_a) |
                   (df_h2h$team_b %in% aliases_a & df_h2h$winner %in% aliases_a), na.rm = TRUE)
    tb_wins <- sum((df_h2h$team_a %in% aliases_b & df_h2h$winner %in% aliases_b) |
                   (df_h2h$team_b %in% aliases_b & df_h2h$winner %in% aliases_b), na.rm = TRUE)
    
    feat_matrix$h2h_a_wins <- ta_wins
    feat_matrix$h2h_b_wins <- tb_wins
    feat_matrix$h2h_a_win_rate <- ta_wins / pmax(1, nrow(df_h2h))
  } else {
    feat_matrix$h2h_matches_before <- 0
    feat_matrix$h2h_a_wins <- 0
    feat_matrix$h2h_b_wins <- 0
    feat_matrix$h2h_a_win_rate <- 0.0
  }
  
  feat_matrix[is.na(feat_matrix)] <- 0
  test_x_mat <- as.matrix(feat_matrix[, feature_cols])
  
  # Predict probabilities
  prob_xgb <- predict(final_model$xgb, xgb.DMatrix(data = test_x_mat))
  prob_rf <- predict(final_model$rf, data.frame(test_x_mat))$predictions[, "1"]
  test_x_scaled <- scale(test_x_mat, center = final_model$scale_means, scale = final_model$scale_sds)
  prob_glm <- predict(final_model$glm, newdata = data.frame(test_x_mat), type = "response")
  if (is.na(prob_glm)) prob_glm <- 0.5
  
  stack_df <- data.frame(xgb = prob_xgb, rf = prob_rf, glm = prob_glm)
  prob_a <- as.numeric(predict(final_model$meta, stack_df, type = "response"))
  prob_b <- 1 - prob_a
  
  winner <- ifelse(prob_a > 0.5, ta_disp, tb_disp)
  conf <- ifelse(abs(prob_a - prob_b) > 0.25, "VERY HIGH", 
                 ifelse(abs(prob_a - prob_b) > 0.15, "HIGH", 
                        ifelse(abs(prob_a - prob_b) > 0.06, "MEDIUM", "LOW (TIGHT CLASH)")))
  
  stat_a <- global_team_stats %>% filter(Team == ta_disp)
  stat_b <- global_team_stats %>% filter(Team == tb_disp)
  
  gf_a <- ifelse(nrow(stat_a) > 0, stat_a$GF_Avg[1], 2.2)
  ga_a <- ifelse(nrow(stat_a) > 0, stat_a$GA_Avg[1], 1.5)
  gf_b <- ifelse(nrow(stat_b) > 0, stat_b$GF_Avg[1], 2.2)
  ga_b <- ifelse(nrow(stat_b) > 0, stat_b$GA_Avg[1], 1.5)
  
  exp_goals_a <- round(pmax(0.5, (gf_a + ga_b) / 2 + (feat_matrix$elo_diff_k20 / 280)), 1)
  exp_goals_b <- round(pmax(0.5, (gf_b + ga_a) / 2 - (feat_matrix$elo_diff_k20 / 280)), 1)
  
  list(
    team_a = ta_disp,
    team_b = tb_disp,
    prob_a = prob_a,
    prob_b = prob_b,
    winner = winner,
    confidence = conf,
    prob_xgb = prob_xgb,
    prob_rf = prob_rf,
    prob_glm = prob_glm,
    feat = feat_matrix,
    h2h_df = df_h2h,
    df_ta = df_ta,
    df_tb = df_tb,
    exp_goals_a = exp_goals_a,
    exp_goals_b = exp_goals_b
  )
}

# ------------------------------------------------------------------------------
# 6. MONTE CARLO TOURNAMENT SIMULATION ENGINE (ULTRA FAST)
# ------------------------------------------------------------------------------
simulate_world_cup <- function(n_sims = 300) {
  teams_16 <- unlist(wc_pools)
  win_counts <- rep(0, length(teams_16))
  podium_counts <- rep(0, length(teams_16))
  semi_counts <- rep(0, length(teams_16))
  names(win_counts) <- teams_16
  names(podium_counts) <- teams_16
  names(semi_counts) <- teams_16
  
  team_elos <- sapply(teams_16, function(t) {
    el <- global_team_stats$ELO[global_team_stats$Team == t]
    if (length(el) == 0) 1500 else el[1]
  })
  
  pair_prob <- matrix(0.5, nrow = 16, ncol = 16, dimnames = list(teams_16, teams_16))
  for (i in 1:16) {
    for (j in 1:16) {
      if (i != j) {
        diff <- team_elos[i] - team_elos[j]
        pair_prob[i, j] <- 1 / (1 + 10^(-diff / 400))
      }
    }
  }
  
  sim_match <- function(t1, t2) {
    p <- pair_prob[t1, t2]
    if (runif(1) < p) t1 else t2
  }
  
  for (s in 1:n_sims) {
    pool_winners <- c()
    pool_runners <- c()
    
    for (p_name in names(wc_pools)) {
      p_teams <- wc_pools[[p_name]]
      points <- rep(0, 4)
      names(points) <- p_teams
      
      for (a in 1:3) {
        for (b in (a+1):4) {
          t_a <- p_teams[a]
          t_b <- p_teams[b]
          p_a_win <- pair_prob[t_a, t_b]
          r <- runif(1)
          if (r < p_a_win * 0.75) {
            points[t_a] <- points[t_a] + 3
          } else if (r > 1 - ((1 - p_a_win) * 0.75)) {
            points[t_b] <- points[t_b] + 3
          } else {
            points[t_a] <- points[t_a] + 1
            points[t_b] <- points[t_b] + 1
          }
        }
      }
      sorted_p <- sort(points + runif(4, 0, 0.1), decreasing = TRUE)
      pool_winners <- c(pool_winners, names(sorted_p)[1])
      pool_runners <- c(pool_runners, names(sorted_p)[2])
    }
    
    qf_teams <- c(pool_winners, pool_runners)
    qf1_w <- sim_match(qf_teams[1], qf_teams[6])
    qf2_w <- sim_match(qf_teams[2], qf_teams[5])
    qf3_w <- sim_match(qf_teams[3], qf_teams[8])
    qf4_w <- sim_match(qf_teams[4], qf_teams[7])
    
    semis <- c(qf1_w, qf2_w, qf3_w, qf4_w)
    for (sm in semis) semi_counts[sm] <- semi_counts[sm] + 1
    
    f1_w <- sim_match(qf1_w, qf2_w)
    f1_l <- ifelse(f1_w == qf1_w, qf2_w, qf1_w)
    f2_w <- sim_match(qf3_w, qf4_w)
    f2_l <- ifelse(f2_w == qf3_w, qf4_w, qf3_w)
    
    champ <- sim_match(f1_w, f2_w)
    runner_up <- ifelse(champ == f1_w, f2_w, f1_w)
    bronze <- sim_match(f1_l, f2_l)
    
    win_counts[champ] <- win_counts[champ] + 1
    podium_counts[champ] <- podium_counts[champ] + 1
    podium_counts[runner_up] <- podium_counts[runner_up] + 1
    podium_counts[bronze] <- podium_counts[bronze] + 1
  }
  
  data.frame(
    Team = teams_16,
    Champ_Prob = round(win_counts / n_sims * 100, 1),
    Podium_Prob = round(podium_counts / n_sims * 100, 1),
    Semi_Prob = round(semi_counts / n_sims * 100, 1)
  ) %>% arrange(desc(Champ_Prob))
}

default_sim_results <- simulate_world_cup(n_sims = 300)

# ------------------------------------------------------------------------------
# 7. HIGH-END VIBRANT SPORTS ANALYTICS THEME & CSS
# ------------------------------------------------------------------------------
custom_css <- "
@import url('https://fonts.googleapis.com/css2?family=Outfit:wght@400;600;700;800;900&family=Inter:wght@400;500;600;700&display=swap');

:root {
  --bg-dark: #0B0F17;
  --card-bg: rgba(21, 28, 44, 0.92);
  --card-border: rgba(56, 189, 248, 0.18);
  --text-main: #FFFFFF;
  --text-sub: #CBD5E1;
  --accent-cyan: #00D2FF;
  --accent-blue: #3B82F6;
  --accent-purple: #8B5CF6;
  --accent-emerald: #10B981;
  --accent-amber: #F59E0B;
  --accent-rose: #FF4B72;
}

body {
  font-family: 'Inter', sans-serif !important;
  background: radial-gradient(circle at 50% 0%, #172033 0%, #0B0F17 75%) !important;
  color: #FFFFFF !important;
  min-height: 100vh;
}

h1, h2, h3, h4, h5, h6, .navbar-brand {
  font-family: 'Outfit', sans-serif !important;
  font-weight: 700;
  letter-spacing: -0.01em;
  color: #FFFFFF !important;
}

.navbar {
  background: rgba(11, 15, 23, 0.95) !important;
  backdrop-filter: blur(20px);
  border-bottom: 1px solid rgba(56, 189, 248, 0.25) !important;
  box-shadow: 0 4px 30px rgba(0, 0, 0, 0.6);
  padding: 12px 20px !important;
}

.navbar-brand {
  font-weight: 900;
  font-size: 1.4rem;
  background: linear-gradient(135deg, #00D2FF 0%, #38BDF8 50%, #A855F7 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  display: flex;
  align-items: center;
  gap: 10px;
}

.nav-link {
  font-weight: 600 !important;
  font-size: 0.95rem;
  color: #CBD5E1 !important;
  transition: all 0.25s ease;
  border-radius: 10px;
  padding: 9px 16px !important;
  margin: 0 4px;
}

.nav-link:hover {
  color: #00D2FF !important;
  background: rgba(0, 210, 255, 0.12);
}

.nav-link.active {
  color: #FFFFFF !important;
  background: linear-gradient(135deg, rgba(37, 99, 235, 0.5) 0%, rgba(139, 92, 246, 0.5) 100%) !important;
  border: 1px solid #00D2FF !important;
  box-shadow: 0 0 18px rgba(0, 210, 255, 0.35);
}

/* Glassmorphism Cards */
.card {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 18px !important;
  backdrop-filter: blur(16px);
  box-shadow: 0 10px 35px rgba(0, 0, 0, 0.45);
  transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease;
}

.card:hover {
  border-color: rgba(0, 210, 255, 0.45) !important;
  box-shadow: 0 14px 45px rgba(0, 0, 0, 0.6);
}

.card-header {
  background: rgba(255, 255, 255, 0.05) !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1) !important;
  font-weight: 700;
  font-size: 1.1rem;
  padding: 16px 22px !important;
  color: #FFFFFF !important;
}

.card-body {
  padding: 22px !important;
  color: #F8FAFC !important;
}

/* Inputs & Dropdowns - High Contrast & Glowing */
.form-control, .form-select, select, .selectize-input {
  background: #151D2E !important;
  border: 1.5px solid rgba(56, 189, 248, 0.3) !important;
  color: #FFFFFF !important;
  border-radius: 12px !important;
  padding: 10px 15px !important;
  font-weight: 600 !important;
  font-size: 0.95rem !important;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
}

.form-control:focus, .form-select:focus, .selectize-input.focus {
  border-color: #00D2FF !important;
  box-shadow: 0 0 0 4px rgba(0, 210, 255, 0.25) !important;
  background: #1A2438 !important;
}

.selectize-dropdown {
  background: #151D2E !important;
  border: 1.5px solid #00D2FF !important;
  border-radius: 12px !important;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.8) !important;
  color: #FFFFFF !important;
}

.selectize-dropdown .option {
  padding: 10px 14px !important;
  color: #F8FAFC !important;
  font-weight: 500;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.selectize-dropdown .active {
  background: linear-gradient(90deg, #0284C7 0%, #0369A1 100%) !important;
  color: #FFFFFF !important;
  font-weight: 700;
}

/* Custom Gradient Metric Value Boxes */
.metric-box-cyan {
  background: linear-gradient(135deg, rgba(6, 182, 212, 0.25) 0%, rgba(59, 130, 246, 0.35) 100%);
  border: 1.5px solid #06B6D4;
  border-radius: 16px;
  padding: 18px 20px;
  box-shadow: 0 6px 20px rgba(6, 182, 212, 0.2);
}

.metric-box-emerald {
  background: linear-gradient(135deg, rgba(16, 185, 129, 0.25) 0%, rgba(5, 150, 105, 0.35) 100%);
  border: 1.5px solid #10B981;
  border-radius: 16px;
  padding: 18px 20px;
  box-shadow: 0 6px 20px rgba(16, 185, 129, 0.2);
}

.metric-box-purple {
  background: linear-gradient(135deg, rgba(139, 92, 246, 0.25) 0%, rgba(124, 58, 237, 0.35) 100%);
  border: 1.5px solid #8B5CF6;
  border-radius: 16px;
  padding: 18px 20px;
  box-shadow: 0 6px 20px rgba(139, 92, 246, 0.2);
}

.metric-box-amber {
  background: linear-gradient(135deg, rgba(245, 158, 11, 0.25) 0%, rgba(217, 119, 6, 0.35) 100%);
  border: 1.5px solid #F59E0B;
  border-radius: 16px;
  padding: 18px 20px;
  box-shadow: 0 6px 20px rgba(245, 158, 11, 0.2);
}

.metric-box-rose {
  background: linear-gradient(135deg, rgba(244, 63, 94, 0.25) 0%, rgba(225, 29, 72, 0.35) 100%);
  border: 1.5px solid #F43F5E;
  border-radius: 16px;
  padding: 18px 20px;
  box-shadow: 0 6px 20px rgba(244, 63, 94, 0.2);
}

.metric-title {
  font-size: 0.85rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-weight: 700;
  color: #CBD5E1;
  margin-bottom: 6px;
}

.metric-value {
  font-size: 1.85rem;
  font-weight: 900;
  font-family: 'Outfit', sans-serif;
  color: #FFFFFF;
}

/* Custom Buttons */
.btn-primary {
  background: linear-gradient(135deg, #0284C7 0%, #2563EB 100%) !important;
  border: 1px solid #38BDF8 !important;
  font-weight: 800 !important;
  border-radius: 12px !important;
  padding: 12px 20px !important;
  box-shadow: 0 4px 20px rgba(2, 132, 199, 0.45);
  color: #FFFFFF !important;
  transition: all 0.25s ease;
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 25px rgba(2, 132, 199, 0.7);
}

/* Badges */
.badge-pill {
  display: inline-block;
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 0.85rem;
  font-weight: 700;
  letter-spacing: 0.03em;
}

.badge-win { background: rgba(16, 185, 129, 0.25); color: #34D399; border: 1.5px solid #10B981; }
.badge-draw { background: rgba(245, 158, 11, 0.25); color: #FBBF24; border: 1.5px solid #F59E0B; }
.badge-loss { background: rgba(244, 63, 94, 0.25); color: #FB7185; border: 1.5px solid #F43F5E; }

/* DataTables Styling */
table.dataTable {
  color: #FFFFFF !important;
  border-collapse: separate !important;
  border-spacing: 0 6px !important;
}

table.dataTable thead th {
  background: rgba(15, 23, 42, 0.95) !important;
  color: #38BDF8 !important;
  border-bottom: 2px solid #00D2FF !important;
  font-weight: 800;
  text-transform: uppercase;
  font-size: 0.82rem;
  letter-spacing: 0.06em;
  padding: 14px 16px !important;
}

table.dataTable tbody tr {
  background: rgba(21, 28, 44, 0.85) !important;
  border-radius: 10px !important;
  transition: all 0.2s ease;
}

table.dataTable tbody tr:hover {
  background: rgba(30, 41, 59, 0.95) !important;
  border-left: 3px solid #00D2FF !important;
}

table.dataTable tbody td {
  padding: 14px 16px !important;
  font-size: 0.92rem;
  color: #F8FAFC !important;
}

/* Banner */
.trophy-banner {
  background: linear-gradient(135deg, rgba(245, 158, 11, 0.2) 0%, rgba(217, 119, 6, 0.35) 100%);
  border: 1.5px solid #F59E0B;
  border-radius: 22px;
  padding: 35px;
  text-align: center;
  box-shadow: 0 10px 40px rgba(245, 158, 11, 0.25);
}
"

# ------------------------------------------------------------------------------
# 8. UI DEFINITION
# ------------------------------------------------------------------------------
ui <- page_navbar(
  theme = bs_theme(
    version = 5,
    bg = "#0B0F17",
    fg = "#FFFFFF",
    primary = "#00D2FF",
    secondary = "#64748B",
    success = "#10B981",
    danger = "#FF4B72",
    warning = "#F59E0B",
    base_font = font_google("Inter"),
    heading_font = font_google("Outfit")
  ),
  title = tags$div(
    class = "navbar-brand",
    tags$i(class = "fa-solid fa-hockey-puck", style = "color: #00D2FF; font-size: 1.6rem; margin-right: 8px;"),
    "HOCKEY INTEL",
    tags$span("2026 WORLD CUP AI", style = "font-size: 0.78rem; background: rgba(0, 210, 255, 0.18); border: 1px solid #00D2FF; color: #00D2FF; padding: 3px 10px; border-radius: 14px; margin-left: 8px; font-weight: 800;")
  ),
  header = tags$head(
    tags$link(rel = "stylesheet", href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"),
    tags$style(HTML(custom_css))
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 1: MATCH PREDICTOR & ARENA
  # ----------------------------------------------------------------------------
  nav_panel("Match Arena", icon = icon("bolt-lightning"),
    layout_sidebar(
      sidebar = sidebar(
        width = 330,
        title = tags$h5(icon("sliders"), " Match Configuration", style = "font-weight: 800; color: #00D2FF; margin: 0;"),
        selectInput("pred_team_a", "Team A (Home / Seed 1):", choices = display_teams_list, selected = "India"),
        selectInput("pred_team_b", "Team B (Away / Seed 2):", choices = display_teams_list, selected = "Pakistan"),
        div(style = "margin-bottom: 12px; display: flex; gap: 6px; flex-wrap: wrap;",
          actionButton("arena_ind_pak", "India vs Pak", class = "btn btn-sm btn-outline-info", style = "font-size: 0.78rem; padding: 3px 8px;"),
          actionButton("arena_aus_ind", "Aus vs India", class = "btn btn-sm btn-outline-info", style = "font-size: 0.78rem; padding: 3px 8px;"),
          actionButton("arena_aus_ned", "Aus vs Ned", class = "btn btn-sm btn-outline-info", style = "font-size: 0.78rem; padding: 3px 8px;"),
          actionButton("arena_ger_bel", "Ger vs Bel", class = "btn btn-sm btn-outline-info", style = "font-size: 0.78rem; padding: 3px 8px;"),
          actionButton("arena_eng_arg", "Eng vs Arg", class = "btn btn-sm btn-outline-info", style = "font-size: 0.78rem; padding: 3px 8px;")
        ),
        dateInput("pred_date", "Match Date:", value = as.Date("2026-08-23")),
        selectInput("pred_tournament", "Tournament Level:", 
                    choices = c("WORLD_CUP" = "FIH Hockey World Cup 2026", 
                                "OLYMPICS" = "Olympic Games", 
                                "PRO_LEAGUE" = "FIH Pro League", 
                                "TEST_MATCH" = "International Test Series",
                                "OTHER" = "Continental Trophy"),
                    selected = "WORLD_CUP"),
        actionButton("run_pred_btn", "SIMULATE CLASH", class = "btn-primary btn-lg", style = "width: 100%; margin-top: 15px; font-size: 1.05rem;"),
        hr(style = "border-color: rgba(255,255,255,0.15);"),
        tags$div(
          style = "font-size: 0.85rem; color: #CBD5E1; line-height: 1.45;",
          tags$strong(icon("circle-info"), " Ensemble AI Engine:"),
          tags$p("Combines XGBoost, Ranger Random Forest (500 trees), and Scaled Logistic Regression trained on 6,608 historical international matches.")
        )
      ),
      
      div(style = "padding: 5px;",
        uiOutput("live_prediction_view")
      )
    )
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 2: 2026 WORLD CUP TOURNAMENT SIMULATOR
  # ----------------------------------------------------------------------------
  nav_panel("World Cup Simulator", icon = icon("trophy"),
    div(style = "padding: 10px 15px;",
      fluidRow(
        column(12,
          div(class = "trophy-banner mb-4",
            tags$i(class = "fa-solid fa-trophy", style = "font-size: 3.2rem; color: #F59E0B; margin-bottom: 12px; filter: drop-shadow(0 0 20px rgba(245, 158, 11, 0.8));"),
            tags$h2("2026 MEN'S FIH HOCKEY WORLD CUP SIMULATOR", style = "font-weight: 900; color: #FFFFFF; margin-bottom: 8px; letter-spacing: -0.01em;"),
            tags$p("Wavre (Belgium) & Amstelveen (Netherlands) • 16 World Contenders • Monte Carlo Engine", style = "color: #E2E8F0; font-size: 1.1rem; margin-bottom: 20px;"),
            fluidRow(
              column(4, offset = 4,
                div(style = "display: flex; gap: 12px; justify-content: center; align-items: center;",
                  sliderInput("sim_iterations", "Monte Carlo Runs:", min = 100, max = 1000, value = 400, step = 50),
                  actionButton("run_sim_btn", "RUN SIMULATION", class = "btn btn-warning btn-md", style = "font-weight: 800; margin-top: 10px; color: #000000;")
                )
              )
            )
          )
        )
      ),
      
      fluidRow(
        column(7,
          card(
            card_header(tags$span(icon("chart-column"), " Championship Win Probability (% Title Odds)")),
            card_body(
              plotlyOutput("sim_champ_chart", height = "450px")
            )
          )
        ),
        column(5,
          card(
            card_header(tags$span(icon("medal"), " Tournament Outcome Forecast Table")),
            card_body(
              DTOutput("sim_table_view")
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(12,
          card(
            card_header(tags$span(icon("sitemap"), " Official Tournament Pools & ELO Leaderboards")),
            card_body(
              uiOutput("pools_cards_view")
            )
          )
        )
      )
    )
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 3: GLOBAL ELO RANKINGS & ANALYTICS
  # ----------------------------------------------------------------------------
  nav_panel("Global Rankings", icon = icon("ranking-star"),
    div(style = "padding: 10px 15px;",
      fluidRow(
        column(3,
          div(class = "metric-box-amber",
            div(class = "metric-title", icon("crown"), " Top Ranked Nation"),
            div(class = "metric-value", textOutput("top_ranked_team"))
          )
        ),
        column(3,
          div(class = "metric-box-cyan",
            div(class = "metric-title", icon("earth-americas"), " Nations Tracked"),
            div(class = "metric-value", length(display_teams_list))
          )
        ),
        column(3,
          div(class = "metric-box-rose",
            div(class = "metric-title", icon("fire"), " Highest Momentum"),
            div(class = "metric-value", textOutput("top_momentum_team"))
          )
        ),
        column(3,
          div(class = "metric-box-emerald",
            div(class = "metric-title", icon("database"), " Most Matches Logged"),
            div(class = "metric-value", paste0(max(global_team_stats$Matches), " (", global_team_stats$Team[which.max(global_team_stats$Matches)], ")"))
          )
        )
      ),
      br(),
      fluidRow(
        column(12,
          card(
            card_header(
              div(style = "display: flex; justify-content: space-between; align-items: center;",
                tags$span(icon("list-ol"), " FIH Men's Senior International ELO Leaderboard"),
                selectInput("continent_filter", NULL, choices = c("All Continents", "Europe", "Asia", "Oceania", "Americas", "Africa"), selected = "All Continents", width = "220px")
              )
            ),
            card_body(
              DTOutput("global_elo_table")
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(6,
          card(
            card_header(tags$span(icon("crosshairs"), " Attacking Power vs Defensive Solidity (Goals/Game)")),
            card_body(
              plotlyOutput("quadrant_plot", height = "430px")
            )
          )
        ),
        column(6,
          card(
            card_header(
              div(style = "display: flex; justify-content: space-between; align-items: center;",
                tags$span(icon("chart-line"), " Historical ELO Rating Progression"),
                selectizeInput("elo_trend_teams", NULL, choices = display_teams_list, selected = c("India", "Australia", "Netherlands", "Belgium", "Germany", "Pakistan"), multiple = TRUE, width = "380px")
              )
            ),
            card_body(
              plotlyOutput("elo_history_chart", height = "430px")
            )
          )
        )
      )
    )
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 4: HEAD-TO-HEAD RIVALRY EXPLORER (FIXED & ENHANCED)
  # ----------------------------------------------------------------------------
  nav_panel("H2H Rivalry", icon = icon("handshake-angle"),
    div(style = "padding: 10px 15px;",
      fluidRow(
        column(5,
          card(
            card_header(tags$span(icon("users"), " Select Rivalry Matchup")),
            card_body(
              fluidRow(
                column(6, selectInput("h2h_team_1", "Team 1:", choices = display_teams_list, selected = "India")),
                column(6, selectInput("h2h_team_2", "Team 2:", choices = display_teams_list, selected = "Pakistan"))
              ),
              div(style = "margin-top: 10px; display: flex; gap: 8px; flex-wrap: wrap;",
                actionButton("quick_ind_pak", "India vs Pakistan", class = "btn btn-sm btn-outline-info"),
                actionButton("quick_aus_ned", "Australia vs Netherlands", class = "btn btn-sm btn-outline-info"),
                actionButton("quick_ger_bel", "Germany vs Belgium", class = "btn btn-sm btn-outline-info"),
                actionButton("quick_eng_arg", "England vs Argentina", class = "btn btn-sm btn-outline-info")
              )
            )
          )
        ),
        column(7,
          uiOutput("h2h_summary_boxes")
        )
      ),
      br(),
      fluidRow(
        column(5,
          card(
            card_header(tags$span(icon("chart-pie"), " Win / Draw / Loss Ratio")),
            card_body(
              plotlyOutput("h2h_donut_plot", height = "360px")
            )
          )
        ),
        column(7,
          card(
            card_header(tags$span(icon("chart-simple"), " Goal Margin Distribution")),
            card_body(
              plotlyOutput("h2h_gd_plot", height = "360px")
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(12,
          card(
            card_header(tags$span(icon("clock-rotate-left"), " Complete Historical Match Record")),
            card_body(
              DTOutput("h2h_table_view")
            )
          )
        )
      )
    )
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 5: 2026 WORLD CUP FIXTURES CENTER
  # ----------------------------------------------------------------------------
  nav_panel("2026 Fixtures Hub", icon = icon("calendar-days"),
    div(style = "padding: 10px 15px;",
      card(
        card_header(
          div(style = "display: flex; justify-content: space-between; align-items: center;",
            tags$span(icon("calendar-check"), " 2026 FIH Hockey World Cup Schedule & ML Forecasts"),
            downloadButton("download_wc_preds", "Export Predictions (CSV)", class = "btn btn-success btn-sm", style = "font-weight: 700;")
          )
        ),
        card_body(
          DTOutput("wc_fixtures_table")
        )
      )
    )
  ),
  
  # ----------------------------------------------------------------------------
  # TAB 6: AI MODEL DIAGNOSTICS & EXPLAINABILITY (VIBRANT & BEAUTIFUL)
  # ----------------------------------------------------------------------------
  nav_panel("AI Diagnostics", icon = icon("microchip"),
    div(style = "padding: 10px 15px;",
      fluidRow(
        column(2,
          div(class = "metric-box-emerald",
            div(class = "metric-title", icon("bullseye"), " Test Accuracy"),
            div(class = "metric-value", "75.20%")
          )
        ),
        column(2,
          div(class = "metric-box-cyan",
            div(class = "metric-title", icon("chart-area"), " ROC-AUC Score"),
            div(class = "metric-value", "83.47%")
          )
        ),
        column(2,
          div(class = "metric-box-purple",
            div(class = "metric-title", icon("scale-balanced"), " Balanced Acc"),
            div(class = "metric-value", "74.77%")
          )
        ),
        column(2,
          div(class = "metric-box-amber",
            div(class = "metric-title", icon("check-double"), " F1 Score"),
            div(class = "metric-value", "0.778")
          )
        ),
        column(2,
          div(class = "metric-box-rose",
            div(class = "metric-title", icon("chart-line"), " Brier Score"),
            div(class = "metric-value", "0.164")
          )
        ),
        column(2,
          div(class = "metric-box-cyan",
            div(class = "metric-title", icon("cubes"), " Features"),
            div(class = "metric-value", "138")
          )
        )
      ),
      br(),
      fluidRow(
        column(7,
          card(
            card_header(tags$span(icon("wand-magic-sparkles"), " Top 20 Most Predictive Features (XGBoost Relative Gain)")),
            card_body(
              plotlyOutput("feature_importance_plot", height = "480px")
            )
          )
        ),
        column(5,
          card(
            card_header(tags$span(icon("diagram-project"), " Super-Learner Ensemble Architecture")),
            card_body(
              div(style = "line-height: 1.65; font-size: 0.95rem; color: #F8FAFC;",
                tags$h5(strong("Multi-Tier Ensemble Model Structure"), style = "color: #00D2FF; margin-bottom: 10px;"),
                tags$div(style = "background: rgba(0, 210, 255, 0.1); border-left: 3px solid #00D2FF; padding: 10px 14px; border-radius: 8px; margin-bottom: 12px;",
                  tags$strong("Base Model 1: XGBoost Booster"), 
                  tags$p("Captures non-linear interactions, rest decay curves, and momentum swings (depth=4, eta=0.03, colsample=0.8).", style = "margin: 0; font-size: 0.88rem; color: #CBD5E1;")
                ),
                tags$div(style = "background: rgba(139, 92, 246, 0.1); border-left: 3px solid #8B5CF6; padding: 10px 14px; border-radius: 8px; margin-bottom: 12px;",
                  tags$strong("Base Model 2: Ranger Random Forest"), 
                  tags$p("500 probability trees evaluating random subsets with variance reduction.", style = "margin: 0; font-size: 0.88rem; color: #CBD5E1;")
                ),
                tags$div(style = "background: rgba(16, 185, 129, 0.1); border-left: 3px solid #10B981; padding: 10px 14px; border-radius: 8px; margin-bottom: 12px;",
                  tags$strong("Base Model 3: Penalized Logistic GLM"), 
                  tags$p("Robust linear baseline calibrated on standardized pre-match feature vectors.", style = "margin: 0; font-size: 0.88rem; color: #CBD5E1;")
                ),
                tags$div(style = "background: rgba(245, 158, 11, 0.1); border-left: 3px solid #F59E0B; padding: 10px 14px; border-radius: 8px;",
                  tags$strong("Meta-Learner: Stacking Logistic Regression"), 
                  tags$p("Optimal out-of-fold probability calibration combining all base learners with zero data leakage.", style = "margin: 0; font-size: 0.88rem; color: #CBD5E1;")
                )
              )
            )
          )
        )
      )
    )
  )
)

# ------------------------------------------------------------------------------
# 9. SERVER LOGIC
# ------------------------------------------------------------------------------
server <- function(input, output, session) {
  
  # Match Arena Quick Presets
  observeEvent(input$arena_ind_pak, {
    updateSelectInput(session, "pred_team_a", selected = "India")
    updateSelectInput(session, "pred_team_b", selected = "Pakistan")
  })
  observeEvent(input$arena_aus_ind, {
    updateSelectInput(session, "pred_team_a", selected = "Australia")
    updateSelectInput(session, "pred_team_b", selected = "India")
  })
  observeEvent(input$arena_aus_ned, {
    updateSelectInput(session, "pred_team_a", selected = "Australia")
    updateSelectInput(session, "pred_team_b", selected = "Netherlands")
  })
  observeEvent(input$arena_ger_bel, {
    updateSelectInput(session, "pred_team_a", selected = "Germany")
    updateSelectInput(session, "pred_team_b", selected = "Belgium")
  })
  observeEvent(input$arena_eng_arg, {
    updateSelectInput(session, "pred_team_a", selected = "England")
    updateSelectInput(session, "pred_team_b", selected = "Argentina")
  })

  # Preset buttons for Rivalry tab
  observeEvent(input$quick_ind_pak, {
    updateSelectInput(session, "h2h_team_1", selected = "India")
    updateSelectInput(session, "h2h_team_2", selected = "Pakistan")
  })
  observeEvent(input$quick_aus_ned, {
    updateSelectInput(session, "h2h_team_1", selected = "Australia")
    updateSelectInput(session, "h2h_team_2", selected = "Netherlands")
  })
  observeEvent(input$quick_ger_bel, {
    updateSelectInput(session, "h2h_team_1", selected = "Germany")
    updateSelectInput(session, "h2h_team_2", selected = "Belgium")
  })
  observeEvent(input$quick_eng_arg, {
    updateSelectInput(session, "h2h_team_1", selected = "England")
    updateSelectInput(session, "h2h_team_2", selected = "Argentina")
  })
  
  # ----------------------------------------------------------------------------
  # TAB 1: MATCH PREDICTOR LOGIC
  # ----------------------------------------------------------------------------
  prediction_reactive <- reactiveVal(NULL)
  
  observe({
    ta <- input$pred_team_a
    tb <- input$pred_team_b
    if (ta == tb) {
      # If user picked same team, automatically adjust team B
      alt_choices <- setdiff(display_teams_list, ta)
      tb <- alt_choices[1]
      updateSelectInput(session, "pred_team_b", selected = tb)
    }
    m_dt <- if (!is.null(input$pred_date) && length(input$pred_date) > 0 && !is.na(input$pred_date)) as.Date(input$pred_date) else as.Date("2026-08-23")
    res <- predict_clash(ta, tb, m_dt)
    prediction_reactive(res)
  }) %>% bindEvent(input$run_pred_btn, ignoreInit = FALSE)
  
  output$live_prediction_view <- renderUI({
    res <- prediction_reactive()
    
    if (is.null(res)) {
      return(
        div(class = "alert alert-info", style = "background: rgba(0,210,255,0.15); border: 1.5px solid #00D2FF; color: #FFFFFF; border-radius: 14px; padding: 22px;",
          tags$h4(icon("circle-info"), " Match Simulator Ready"),
          tags$p("Select any two teams above or click one of the quick match buttons to simulate!")
        )
      )
    }
    
    ta <- res$team_a
    tb <- res$team_b
    prob_a <- res$prob_a
    prob_b <- res$prob_b
    winner <- res$winner
    
    color_a <- ifelse(winner == ta, "#00D2FF", "#94A3B8")
    color_b <- ifelse(winner == tb, "#FF4B72", "#94A3B8")
    winner_color <- ifelse(winner == ta, "#00D2FF", "#FF4B72")
    
    tagList(
      fluidRow(
        column(12,
          card(
            card_body(
              fluidRow(
                column(4, style = "text-align: center;",
                  tags$h2(ta, style = sprintf("font-weight: 900; color: %s; margin-bottom: 4px; font-size: 2.2rem;", color_a)),
                  tags$span(sprintf("Win Probability: %.1f%%", prob_a * 100), style = "font-size: 1.3rem; font-weight: 800; color: #FFFFFF;"),
                  tags$p(sprintf("Expected Goals: ~%.1f", res$exp_goals_a), style = "color: #CBD5E1; font-size: 1rem; margin-top: 4px;")
                ),
                column(4, style = "text-align: center; display: flex; flex-direction: column; justify-content: center; align-items: center;",
                  tags$div(style = "font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.12em; color: #CBD5E1; font-weight: 700;", "AI PROJECTED WINNER"),
                  tags$h1(icon("trophy"), " ", winner, style = sprintf("color: %s; font-weight: 900; margin: 8px 0; font-size: 2.3rem; filter: drop-shadow(0 0 15px %s);", winner_color, winner_color)),
                  tags$div(class = "badge-pill", style = sprintf("background: rgba(%s, 0.3); color: %s; border: 1.5px solid %s;", 
                                                                ifelse(res$confidence %in% c("HIGH", "VERY HIGH"), "16,185,129", "245,158,11"),
                                                                ifelse(res$confidence %in% c("HIGH", "VERY HIGH"), "#34D399", "#FBBF24"),
                                                                ifelse(res$confidence %in% c("HIGH", "VERY HIGH"), "#10B981", "#F59E0B")),
                           paste0("CONFIDENCE: ", res$confidence))
                ),
                column(4, style = "text-align: center;",
                  tags$h2(tb, style = sprintf("font-weight: 900; color: %s; margin-bottom: 4px; font-size: 2.2rem;", color_b)),
                  tags$span(sprintf("Win Probability: %.1f%%", prob_b * 100), style = "font-size: 1.3rem; font-weight: 800; color: #FFFFFF;"),
                  tags$p(sprintf("Expected Goals: ~%.1f", res$exp_goals_b), style = "color: #CBD5E1; font-size: 1rem; margin-top: 4px;")
                )
              ),
              br(),
              tags$div(
                style = "height: 32px; border-radius: 16px; overflow: hidden; display: flex; background: #151D2E; box-shadow: inset 0 2px 8px rgba(0,0,0,0.6);",
                tags$div(
                  style = sprintf("width: %f%%; background: linear-gradient(90deg, #0284C7 0%, #00D2FF 100%); display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 0.95rem; color: #FFFFFF;", prob_a * 100),
                  sprintf("%s %.1f%%", ta, prob_a * 100)
                ),
                tags$div(
                  style = sprintf("width: %f%%; background: linear-gradient(90deg, #FF4B72 0%, #E11D48 100%); display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 0.95rem; color: #FFFFFF;", prob_b * 100),
                  sprintf("%s %.1f%%", tb, prob_b * 100)
                )
              )
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(6,
          card(
            card_header(tags$span(icon("spider"), " Team Radar Attributes Comparison")),
            card_body(
              plotlyOutput("match_radar_plot", height = "380px")
            )
          )
        ),
        column(6,
          card(
            card_header(tags$span(icon("layer-group"), " Multi-Model Probability Breakdown")),
            card_body(
              plotlyOutput("multi_model_breakdown_plot", height = "380px")
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(6,
          card(
            card_header(tags$span(icon("timeline"), " Recent Form & Encounters")),
            card_body(
              tags$h6(strong(paste0(ta, " Recent Form:")), style = "color: #00D2FF; margin-bottom: 8px; font-weight: 700;"),
              uiOutput("form_badges_a"),
              hr(style = "border-color: rgba(255,255,255,0.1);"),
              tags$h6(strong(paste0(tb, " Recent Form:")), style = "color: #FF4B72; margin-bottom: 8px; font-weight: 700;"),
              uiOutput("form_badges_b"),
              hr(style = "border-color: rgba(255,255,255,0.1);"),
              tags$h6(strong("Historical Head-to-Head Record:"), style = "color: #FFFFFF; font-weight: 700;"),
              uiOutput("h2h_brief_summary")
            )
          )
        ),
        column(6,
          card(
            card_header(tags$span(icon("scale-unbalanced"), " Decisive Match Drivers")),
            card_body(
              plotlyOutput("feature_drivers_plot", height = "260px")
            )
          )
        )
      )
    )
  })
  
  output$match_radar_plot <- renderPlotly({
    res <- prediction_reactive()
    req(res)
    
    stat_a <- global_team_stats %>% filter(Team == res$team_a)
    stat_b <- global_team_stats %>% filter(Team == res$team_b)
    
    elo_a_norm <- pmin(100, pmax(0, (res$feat$team_a_elo_k20 - 1300) / 7))
    elo_b_norm <- pmin(100, pmax(0, (res$feat$team_b_elo_k20 - 1300) / 7))
    
    win_a_norm <- ifelse(nrow(stat_a) > 0, stat_a$Win_Pct[1], 50)
    win_b_norm <- ifelse(nrow(stat_b) > 0, stat_b$Win_Pct[1], 50)
    
    gf_a_norm <- ifelse(nrow(stat_a) > 0, pmin(100, stat_a$GF_Avg[1] * 20), 50)
    gf_b_norm <- ifelse(nrow(stat_b) > 0, pmin(100, stat_b$GF_Avg[1] * 20), 50)
    
    def_a_norm <- ifelse(nrow(stat_a) > 0, pmax(0, 100 - (stat_a$GA_Avg[1] * 20)), 50)
    def_b_norm <- ifelse(nrow(stat_b) > 0, pmax(0, 100 - (stat_b$GA_Avg[1] * 20)), 50)
    
    mom_a_norm <- pmin(100, pmax(0, (res$feat$team_a_momentum_win_rate + 0.5) * 100))
    mom_b_norm <- pmin(100, pmax(0, (res$feat$team_b_momentum_win_rate + 0.5) * 100))
    
    categories <- c("ELO Rating", "All-Time Win %", "Attack Power", "Defensive Wall", "Momentum")
    
    fig <- plot_ly(type = 'scatterpolar', fill = 'toself')
    fig <- fig %>% add_trace(
      r = c(elo_a_norm, win_a_norm, gf_a_norm, def_a_norm, mom_a_norm, elo_a_norm),
      theta = c(categories, categories[1]),
      name = res$team_a,
      fillcolor = 'rgba(0, 210, 255, 0.35)',
      line = list(color = '#00D2FF', width = 3)
    )
    fig <- fig %>% add_trace(
      r = c(elo_b_norm, win_b_norm, gf_b_norm, def_b_norm, mom_b_norm, elo_b_norm),
      theta = c(categories, categories[1]),
      name = res$team_b,
      fillcolor = 'rgba(255, 75, 114, 0.35)',
      line = list(color = '#FF4B72', width = 3)
    )
    fig %>% layout(
      polar = list(
        radialaxis = list(visible = TRUE, range = c(0, 100), color = "#94A3B8", gridcolor = "rgba(255,255,255,0.1)"),
        angularaxis = list(color = "#FFFFFF", gridcolor = "rgba(255,255,255,0.1)")
      ),
      paper_bgcolor = 'transparent',
      plot_bgcolor = 'transparent',
      legend = list(font = list(color = '#FFFFFF', size = 12), orientation = "h", x = 0.2, y = -0.1),
      margin = list(t = 20, b = 20, l = 40, r = 40)
    )
  })
  
  output$multi_model_breakdown_plot <- renderPlotly({
    res <- prediction_reactive()
    req(res)
    
    models_df <- data.frame(
      Model = c("V4 Stacked Meta", "XGBoost Classifier", "Random Forest (Ranger)", "Logistic Regression"),
      Prob_A = c(res$prob_a, res$prob_xgb, res$prob_rf, res$prob_glm) * 100,
      Prob_B = c(res$prob_b, 1 - res$prob_xgb, 1 - res$prob_rf, 1 - res$prob_glm) * 100
    )
    
    plot_ly(models_df, x = ~Prob_A, y = ~Model, type = 'bar', orientation = 'h', name = res$team_a,
            marker = list(color = '#00D2FF')) %>%
      add_trace(x = ~Prob_B, name = res$team_b, marker = list(color = '#FF4B72')) %>%
      layout(
        barmode = 'stack',
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = "Win Probability (%)", range = c(0, 100), color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "", color = "#FFFFFF"),
        legend = list(font = list(color = '#FFFFFF'), orientation = "h", y = 1.15),
        margin = list(l = 160, r = 20, t = 30, b = 40)
      )
  })
  
  output$form_badges_a <- renderUI({
    res <- prediction_reactive()
    req(res)
    aliases_a <- get_db_aliases(res$team_a)
    last_5 <- tail(res$df_ta, 5)
    if (nrow(last_5) == 0) return(tags$span("No recent matches"))
    
    badges <- lapply(1:nrow(last_5), function(i) {
      m <- last_5[i, ]
      is_win <- (!is.na(m$winner) && m$winner %in% aliases_a && m$result != "DRAW")
      is_draw <- (m$result == "DRAW")
      opp_raw <- ifelse(m$team_a %in% aliases_a, m$team_b, m$team_a)
      opp_disp <- ifelse(opp_raw %in% names(code_to_display), code_to_display[[opp_raw]], opp_raw)
      
      b_class <- ifelse(is_win, "badge-win", ifelse(is_draw, "badge-draw", "badge-loss"))
      b_text <- ifelse(is_win, paste0("W vs ", opp_disp), ifelse(is_draw, paste0("D vs ", opp_disp), paste0("L vs ", opp_disp)))
      tags$span(class = paste("badge-pill me-1 mb-1", b_class), b_text)
    })
    tagList(badges)
  })
  
  output$form_badges_b <- renderUI({
    res <- prediction_reactive()
    req(res)
    aliases_b <- get_db_aliases(res$team_b)
    last_5 <- tail(res$df_tb, 5)
    if (nrow(last_5) == 0) return(tags$span("No recent matches"))
    
    badges <- lapply(1:nrow(last_5), function(i) {
      m <- last_5[i, ]
      is_win <- (!is.na(m$winner) && m$winner %in% aliases_b && m$result != "DRAW")
      is_draw <- (m$result == "DRAW")
      opp_raw <- ifelse(m$team_a %in% aliases_b, m$team_b, m$team_a)
      opp_disp <- ifelse(opp_raw %in% names(code_to_display), code_to_display[[opp_raw]], opp_raw)
      
      b_class <- ifelse(is_win, "badge-win", ifelse(is_draw, "badge-draw", "badge-loss"))
      b_text <- ifelse(is_win, paste0("W vs ", opp_disp), ifelse(is_draw, paste0("D vs ", opp_disp), paste0("L vs ", opp_disp)))
      tags$span(class = paste("badge-pill me-1 mb-1", b_class), b_text)
    })
    tagList(badges)
  })
  
  output$h2h_brief_summary <- renderUI({
    res <- prediction_reactive()
    req(res)
    h2h <- res$h2h_df
    aliases_a <- get_db_aliases(res$team_a)
    aliases_b <- get_db_aliases(res$team_b)
    
    if (nrow(h2h) == 0) {
      return(tags$p("No prior direct encounters found in database.", style = "color: #CBD5E1;"))
    }
    ta_w <- sum(h2h$winner %in% aliases_a, na.rm = TRUE)
    tb_w <- sum(h2h$winner %in% aliases_b, na.rm = TRUE)
    dr <- sum(h2h$result == "DRAW", na.rm = TRUE)
    
    tags$div(style = "font-size: 1rem; color: #FFFFFF; font-weight: 600;",
      sprintf("Total %d Matches: %s %d wins | %s %d wins | %d Draws", 
              nrow(h2h), res$team_a, ta_w, res$team_b, tb_w, dr)
    )
  })
  
  output$feature_drivers_plot <- renderPlotly({
    res <- prediction_reactive()
    req(res)
    
    feat <- res$feat
    drivers <- data.frame(
      Factor = c("ELO Gap (K=20)", "Rest Advantage", "Win Momentum", "EWMA Goal Diff", "Experience Gap"),
      Advantage = c(
        feat$elo_diff_k20 / 10,
        feat$rest_days_diff * 2,
        (feat$team_a_momentum_win_rate - feat$team_b_momentum_win_rate) * 50,
        (feat$team_a_ewma_gd - feat$team_b_ewma_gd) * 15,
        feat$exp_diff / 5
      )
    )
    
    drivers$Color <- ifelse(drivers$Advantage >= 0, '#00D2FF', '#FF4B72')
    
    plot_ly(drivers, x = ~Advantage, y = ~reorder(Factor, Advantage), type = 'bar', orientation = 'h',
            marker = list(color = ~Color)) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = sprintf("<- Favors %s | Favors %s ->", res$team_b, res$team_a), color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "", color = "#FFFFFF"),
        margin = list(l = 160, r = 20, t = 10, b = 40)
      )
  })
  
  # ----------------------------------------------------------------------------
  # TAB 2: WORLD CUP SIMULATOR LOGIC
  # ----------------------------------------------------------------------------
  sim_results_reactive <- reactiveVal(default_sim_results)
  
  observeEvent(input$run_sim_btn, {
    withProgress(message = "Simulating 2026 World Cup Tournament...", value = 0.3, {
      sim_data <- simulate_world_cup(n_sims = input$sim_iterations)
      incProgress(0.7)
      sim_results_reactive(sim_data)
    })
  })
  
  output$sim_champ_chart <- renderPlotly({
    sim_data <- sim_results_reactive()
    plot_ly(sim_data, x = ~Champ_Prob, y = ~reorder(Team, Champ_Prob), type = 'bar', orientation = 'h',
            marker = list(
              color = ~Champ_Prob,
              colorscale = list(c(0, '#151D2E'), c(0.25, '#0284C7'), c(0.65, '#8B5CF6'), c(1, '#F59E0B')),
              showscale = FALSE
            ),
            text = ~paste0(Champ_Prob, "%"), textposition = 'auto') %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = "Championship Probability (%)", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "", color = "#FFFFFF"),
        margin = list(l = 130, r = 20, t = 20, b = 40)
      )
  })
  
  output$sim_table_view <- renderDT({
    sim_data <- sim_results_reactive()
    datatable(
      sim_data,
      options = list(pageLength = 8, dom = 'tip', ordering = TRUE),
      rownames = FALSE,
      class = 'display compact nowrap'
    ) %>%
      formatStyle('Champ_Prob',
        background = styleColorBar(range(sim_data$Champ_Prob), '#F59E0B'),
        backgroundSize = '98% 70%',
        backgroundRepeat = 'no-repeat',
        backgroundPosition = 'center'
      )
  })
  
  output$pools_cards_view <- renderUI({
    pool_cards <- lapply(names(wc_pools), function(p_name) {
      teams_in_pool <- wc_pools[[p_name]]
      pool_stats <- global_team_stats %>% filter(Team %in% teams_in_pool) %>% arrange(desc(ELO))
      
      column(3,
        card(
          card_header(tags$span(style = "color: #00D2FF; font-weight: 800;", p_name)),
          card_body(
            tags$ul(style = "list-style-type: none; padding-left: 0; margin-bottom: 0;",
              lapply(1:nrow(pool_stats), function(idx) {
                row <- pool_stats[idx, ]
                tags$li(style = "display: flex; justify-content: space-between; padding: 7px 0; border-bottom: 1px solid rgba(255,255,255,0.08);",
                  tags$span(paste0(idx, ". ", row$Team), style = ifelse(idx == 1, "font-weight: 800; color: #F59E0B;", "color: #FFFFFF; font-weight: 600;")),
                  tags$span(paste0("ELO ", round(row$ELO)), style = "color: #38BDF8; font-size: 0.9rem; font-weight: 700;")
                )
              })
            )
          )
        )
      )
    })
    fluidRow(pool_cards)
  })
  
  # ----------------------------------------------------------------------------
  # TAB 3: GLOBAL ELO RANKINGS LOGIC
  # ----------------------------------------------------------------------------
  output$top_ranked_team <- renderText({
    paste0(global_team_stats$Team[1], " (", round(global_team_stats$ELO[1]), ")")
  })
  
  output$top_momentum_team <- renderText({
    best_mom <- global_team_stats %>% arrange(desc(Momentum)) %>% slice(1)
    paste0(best_mom$Team, " (+", best_mom$Momentum, ")")
  })
  
  filtered_elo_data <- reactive({
    data <- global_team_stats
    if (input$continent_filter != "All Continents") {
      data <- data %>% filter(Continent == input$continent_filter)
    }
    data
  })
  
  output$global_elo_table <- renderDT({
    datatable(
      filtered_elo_data(),
      options = list(pageLength = 10, scrollX = TRUE, dom = 'lftip'),
      rownames = FALSE,
      class = 'display compact nowrap'
    ) %>%
      formatStyle('ELO',
        background = styleColorBar(range(global_team_stats$ELO), '#00D2FF'),
        backgroundSize = '98% 70%',
        backgroundRepeat = 'no-repeat',
        backgroundPosition = 'center'
      )
  })
  
  output$quadrant_plot <- renderPlotly({
    plot_data <- global_team_stats %>% filter(Matches >= 15)
    mean_gf <- mean(plot_data$GF_Avg)
    mean_ga <- mean(plot_data$GA_Avg)
    
    plot_ly(plot_data, x = ~GA_Avg, y = ~GF_Avg, text = ~paste0(Team, "<br>ELO: ", ELO, "<br>Matches: ", Matches),
            type = 'scatter', mode = 'markers+text', textposition = 'top right',
            marker = list(
              size = ~pmax(9, sqrt(Matches) * 2.2),
              color = ~ELO,
              colorscale = 'Electric',
              showscale = TRUE,
              colorbar = list(title = "ELO", len = 0.8)
            )) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = "Goals Conceded / Match (Lower is Better Defense)", autorange = "reversed", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "Goals Scored / Match (Higher is Better Attack)", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        shapes = list(
          list(type = "line", x0 = mean_ga, x1 = mean_ga, y0 = min(plot_data$GF_Avg), y1 = max(plot_data$GF_Avg),
               line = list(dash = "dash", color = "rgba(255,255,255,0.25)")),
          list(type = "line", x0 = min(plot_data$GA_Avg), x1 = max(plot_data$GA_Avg), y0 = mean_gf, y1 = mean_gf,
               line = list(dash = "dash", color = "rgba(255,255,255,0.25)"))
        ),
        margin = list(l = 50, r = 20, t = 20, b = 50)
      )
  })
  
  output$elo_history_chart <- renderPlotly({
    selected <- input$elo_trend_teams
    req(selected)
    
    trend_list <- list()
    for (disp_name in selected) {
      aliases <- get_db_aliases(disp_name)
      sub_m <- df %>% filter(team_a %in% aliases | team_b %in% aliases) %>% arrange(match_date)
      if (nrow(sub_m) > 0) {
        dates <- sub_m$match_date
        elos <- ifelse(sub_m$team_a %in% aliases, sub_m$team_a_elo_k20, sub_m$team_b_elo_k20)
        trend_list[[disp_name]] <- data.frame(Date = dates, ELO = elos, Team = disp_name)
      }
    }
    
    if (length(trend_list) == 0) return(NULL)
    trend_df <- bind_rows(trend_list)
    
    plot_ly(trend_df, x = ~Date, y = ~ELO, color = ~Team, type = 'scatter', mode = 'lines',
            line = list(width = 3)) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = "Historical Timeline (2012 - 2026)", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "ELO Rating (K=20)", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        legend = list(font = list(color = '#FFFFFF'), orientation = "h", y = 1.15),
        margin = list(l = 50, r = 20, t = 30, b = 40)
      )
  })
  
  # ----------------------------------------------------------------------------
  # TAB 4: HEAD-TO-HEAD RIVALRY LOGIC (WITH ALIAS RESOLUTION)
  # ----------------------------------------------------------------------------
  h2h_data_reactive <- reactive({
    t1 <- input$h2h_team_1
    t2 <- input$h2h_team_2
    req(t1, t2)
    
    aliases_1 <- get_db_aliases(t1)
    aliases_2 <- get_db_aliases(t2)
    
    df %>% filter((team_a %in% aliases_1 & team_b %in% aliases_2) | 
                  (team_a %in% aliases_2 & team_b %in% aliases_1)) %>% arrange(desc(match_date))
  })
  
  output$h2h_summary_boxes <- renderUI({
    h2h <- h2h_data_reactive()
    t1 <- input$h2h_team_1
    t2 <- input$h2h_team_2
    
    aliases_1 <- get_db_aliases(t1)
    aliases_2 <- get_db_aliases(t2)
    
    t1_wins <- sum(h2h$winner %in% aliases_1, na.rm = TRUE)
    t2_wins <- sum(h2h$winner %in% aliases_2, na.rm = TRUE)
    draws <- sum(h2h$result == "DRAW", na.rm = TRUE)
    
    fluidRow(
      column(4,
        div(class = "metric-box-cyan",
          div(class = "metric-title", icon("trophy"), paste0(" ", t1, " Wins")),
          div(class = "metric-value", t1_wins)
        )
      ),
      column(4,
        div(class = "metric-box-amber",
          div(class = "metric-title", icon("handshake"), " Draws"),
          div(class = "metric-value", draws)
        )
      ),
      column(4,
        div(class = "metric-box-rose",
          div(class = "metric-title", icon("trophy"), paste0(" ", t2, " Wins")),
          div(class = "metric-value", t2_wins)
        )
      )
    )
  })
  
  output$h2h_donut_plot <- renderPlotly({
    h2h <- h2h_data_reactive()
    t1 <- input$h2h_team_1
    t2 <- input$h2h_team_2
    
    aliases_1 <- get_db_aliases(t1)
    aliases_2 <- get_db_aliases(t2)
    
    if (nrow(h2h) == 0) {
      return(
        plot_ly() %>% layout(
          paper_bgcolor = 'transparent',
          plot_bgcolor = 'transparent',
          annotations = list(list(text = "No direct matches recorded", showarrow = FALSE, font = list(color = "#CBD5E1", size = 16)))
        )
      )
    }
    
    t1_wins <- sum(h2h$winner %in% aliases_1, na.rm = TRUE)
    t2_wins <- sum(h2h$winner %in% aliases_2, na.rm = TRUE)
    draws <- sum(h2h$result == "DRAW", na.rm = TRUE)
    
    plot_ly(labels = c(paste0(t1, " Wins"), "Draws", paste0(t2, " Wins")),
            values = c(t1_wins, draws, t2_wins),
            type = 'pie', hole = 0.58,
            marker = list(colors = c('#00D2FF', '#F59E0B', '#FF4B72'))) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        legend = list(font = list(color = '#FFFFFF', size = 12), orientation = "h", y = -0.1),
        margin = list(t = 10, b = 20, l = 20, r = 20)
      )
  })
  
  output$h2h_gd_plot <- renderPlotly({
    h2h <- h2h_data_reactive()
    t1 <- input$h2h_team_1
    t2 <- input$h2h_team_2
    aliases_1 <- get_db_aliases(t1)
    
    if (nrow(h2h) == 0) {
      return(
        plot_ly() %>% layout(
          paper_bgcolor = 'transparent',
          plot_bgcolor = 'transparent',
          annotations = list(list(text = "No direct matches recorded", showarrow = FALSE, font = list(color = "#CBD5E1", size = 16)))
        )
      )
    }
    
    gd <- ifelse(h2h$team_a %in% aliases_1, h2h$goal_difference, -h2h$goal_difference)
    gd_df <- data.frame(Margin = gd)
    
    plot_ly(gd_df, x = ~Margin, type = 'histogram',
            marker = list(color = '#8B5CF6', line = list(color = '#C084FC', width = 1.5))) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = sprintf("Goal Margin (Positive Favors %s, Negative Favors %s)", t1, t2), color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "Match Count", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        margin = list(l = 50, r = 20, t = 10, b = 40)
      )
  })
  
  output$h2h_table_view <- renderDT({
    h2h <- h2h_data_reactive()
    if (nrow(h2h) == 0) {
      return(datatable(data.frame(Status = "No historical matches found between selected teams.")))
    }
    
    display_df <- h2h %>% mutate(
      Team_A_Disp = ifelse(team_a %in% names(code_to_display), code_to_display[[team_a]], team_a),
      Team_B_Disp = ifelse(team_b %in% names(code_to_display), code_to_display[[team_b]], team_b),
      Winner_Disp = ifelse(winner %in% names(code_to_display), code_to_display[[winner]], winner)
    ) %>% select(
      Date = match_date,
      Tournament = tournament,
      Team_A = Team_A_Disp,
      Score_A = team_a_score,
      Score_B = team_b_score,
      Team_B = Team_B_Disp,
      Winner = Winner_Disp,
      Venue = venue
    )
    
    datatable(display_df, options = list(pageLength = 8, dom = 'tip'), rownames = FALSE, class = 'display compact nowrap')
  })
  
  # ----------------------------------------------------------------------------
  # TAB 5: 2026 WORLD CUP FIXTURES LOGIC
  # ----------------------------------------------------------------------------
  wc_fixtures_data <- reactive({
    if (file.exists(fixtures_path)) {
      fix <- read.csv(fixtures_path, stringsAsFactors = FALSE)
    } else {
      fix <- data.frame(
        match_id = paste0("WC26_", 1:8),
        date = c("2026-08-22", "2026-08-22", "2026-08-23", "2026-08-23", "2026-08-24", "2026-08-24", "2026-08-26", "2026-08-28"),
        team_a = c("Ireland", "Netherlands", "Belgium", "Australia", "Argentina", "New Zealand", "France", "Belgium"),
        team_b = c("Spain", "Japan", "Germany", "India", "England", "South Africa", "Malaysia", "Netherlands"),
        venue = c("Wavre, Belgium", "Amstelveen, Netherlands", "Wavre, Belgium", "Amstelveen, Netherlands", "Wavre, Belgium", "Amstelveen, Netherlands", "Wavre, Belgium", "Wavre, Belgium"),
        stage = c("Pool", "Pool", "Pool", "Pool", "Pool", "Pool", "Crossover", "Semi-Final")
      )
    }
    
    preds_list <- list()
    for (i in 1:nrow(fix)) {
      m <- fix[i, ]
      ta_disp <- ifelse(m$team_a %in% names(code_to_display), code_to_display[[m$team_a]], m$team_a)
      tb_disp <- ifelse(m$team_b %in% names(code_to_display), code_to_display[[m$team_b]], m$team_b)
      
      clash <- predict_clash(ta_disp, tb_disp, as.Date(m$date))
      
      if (!is.null(clash)) {
        preds_list[[i]] <- data.frame(
          Match_ID = m$match_id,
          Date = m$date,
          Stage = m$stage,
          Team_A = ta_disp,
          Prob_A = paste0(round(clash$prob_a * 100, 1), "%"),
          Predicted_Winner = clash$winner,
          Prob_B = paste0(round(clash$prob_b * 100, 1), "%"),
          Team_B = tb_disp,
          Confidence = clash$confidence,
          Venue = m$venue,
          stringsAsFactors = FALSE
        )
      }
    }
    bind_rows(preds_list)
  })
  
  output$wc_fixtures_table <- renderDT({
    data <- wc_fixtures_data()
    datatable(data, options = list(pageLength = 10, dom = 'lftip', scrollX = TRUE), rownames = FALSE, class = 'display compact nowrap') %>%
      formatStyle('Confidence',
        backgroundColor = styleEqual(c('VERY HIGH', 'HIGH', 'MEDIUM', 'LOW (TIGHT CLASH)'), 
                                     c('rgba(16,185,129,0.35)', 'rgba(0,210,255,0.35)', 'rgba(245,158,11,0.35)', 'rgba(244,63,94,0.35)'))
      )
  })
  
  output$download_wc_preds <- downloadHandler(
    filename = function() { paste0("world_cup_2026_ml_predictions_", Sys.Date(), ".csv") },
    content = function(file) {
      write.csv(wc_fixtures_data(), file, row.names = FALSE)
    }
  )
  
  # ----------------------------------------------------------------------------
  # TAB 6: AI DIAGNOSTICS & FEATURE IMPORTANCE
  # ----------------------------------------------------------------------------
  output$feature_importance_plot <- renderPlotly({
    imp <- xgb.importance(feature_names = final_model$feature_cols, model = final_model$xgb)
    top20 <- head(imp, 20)
    top20$Clean_Feature <- gsub("_", " ", toupper(top20$Feature))
    
    plot_ly(top20, x = ~Gain, y = ~reorder(Clean_Feature, Gain), type = 'bar', orientation = 'h',
            marker = list(
              color = ~Gain,
              colorscale = list(c(0, '#0284C7'), c(0.4, '#00D2FF'), c(0.7, '#8B5CF6'), c(1, '#F59E0B')),
              showscale = FALSE
            )) %>%
      layout(
        paper_bgcolor = 'transparent',
        plot_bgcolor = 'transparent',
        xaxis = list(title = "Relative Gain Contribution in XGBoost", color = "#CBD5E1", gridcolor = "rgba(255,255,255,0.1)"),
        yaxis = list(title = "", color = "#FFFFFF"),
        margin = list(l = 220, r = 20, t = 20, b = 40)
      )
  })
}

# ------------------------------------------------------------------------------
# 10. RUN SHINY APPLICATION
# ------------------------------------------------------------------------------
shinyApp(ui = ui, server = server)
