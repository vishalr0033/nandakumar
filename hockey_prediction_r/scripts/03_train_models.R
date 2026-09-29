# scripts/03_train_models.R

suppressPackageStartupMessages({
  library(dplyr)
  library(ranger)
  library(xgboost)
  library(jsonlite)
})

cat("========================================\n")
cat("TRAINING MODELS\n")
cat("========================================\n")

df <- readRDS("data/hockey_matches_features.rds")

# Ensure ordered
df <- df %>% arrange(match_date)

# Drop any rows where team_a_win_binary is NA
df <- df %>% filter(!is.na(team_a_win_binary))

# Define Features
feature_cols <- c(
  "elo_difference", 
  "team_a_elo", "team_b_elo",
  "team_a_win_rate", "team_b_win_rate",
  "team_a_form_5", "team_b_form_5",
  "team_a_form_10", "team_b_form_10",
  "team_a_avg_gd", "team_b_avg_gd",
  "team_a_recent_gd", "team_b_recent_gd",
  "team_a_h2h_win_rate",
  "team_a_matches", "team_b_matches",
  "h2h_matches"
)

# Impute NA features safely (from very early matches)
for(col in feature_cols) {
  df[[col]][is.na(df[[col]])] <- 0
}

# Add target as factor for classification
df$target_fct <- as.factor(ifelse(df$team_a_win_binary == 1, "Win", "NotWin"))

# Chronological split
n <- nrow(df)
idx_train_end <- floor(0.70 * n)
idx_val_end <- floor(0.85 * n)

train_df <- df[1:idx_train_end, ]
val_df <- df[(idx_train_end + 1):idx_val_end, ]
test_df <- df[(idx_val_end + 1):n, ]

# Save Split Report
split_report <- "reports/data_split_report.txt"
sink(split_report)
cat("CHRONOLOGICAL SPLIT REPORT\n")
cat("====================================\n")
cat(sprintf("Total Matches: %d\n", n))
cat(sprintf("Train: %d (%s to %s)\n", nrow(train_df), min(train_df$match_date), max(train_df$match_date)))
cat(sprintf("Validation: %d (%s to %s)\n", nrow(val_df), min(val_df$match_date), max(val_df$match_date)))
cat(sprintf("Test: %d (%s to %s)\n", nrow(test_df), min(test_df$match_date), max(test_df$match_date)))
sink()
cat(sprintf("Saved split report to %s\n", split_report))

# Ensure train, val, test saved for eval
saveRDS(train_df, "data/train_df.rds")
saveRDS(val_df, "data/val_df.rds")
saveRDS(test_df, "data/test_df.rds")

# Prepare train matrices
train_x <- as.matrix(train_df[, feature_cols])
train_y <- train_df$team_a_win_binary

# 1. Logistic Regression
cat("Training Logistic Regression...\n")
model_logreg <- glm(team_a_win_binary ~ ., data = train_df[, c(feature_cols, "team_a_win_binary")], family = binomial)
saveRDS(model_logreg, "models/model_logreg.rds")

# 2. Ranger (Random Forest)
cat("Training Random Forest (Ranger) - CPU SAFE...\n")
model_ranger <- ranger(
  formula = target_fct ~ ., 
  data = train_df[, c(feature_cols, "target_fct")],
  num.trees = 200,
  num.threads = 1,      # STRICTLY ONE THREAD
  probability = TRUE,
  importance = 'impurity',
  seed = 42
)
saveRDS(model_ranger, "models/model_ranger.rds")

# 3. XGBoost
cat("Training XGBoost - CPU SAFE...\n")
dtrain <- xgb.DMatrix(data = train_x, label = train_y)
params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 4,
  eta = 0.1,
  nthread = 1          # STRICTLY ONE THREAD
)

set.seed(42)
model_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 150,
  verbose = 0
)
saveRDS(model_xgb, "models/model_xgb.rds")

cat("Model training complete.\n")
