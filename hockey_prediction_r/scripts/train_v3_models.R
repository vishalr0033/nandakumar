# scripts/train_v3_models.R
suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(xgboost)
})

cat("========================================\n")
cat("TRAINING V3 HIGH-ACCURACY 3-CLASS MODEL\n")
cat("========================================\n")

file_path <- "data/hockey_prediction_dataset_v3.xlsx"
df <- read_excel(file_path)

# Label Target (Binary: 1 = Team A Win, 0 = Not Team A Win)
df$team_a_win_binary <- ifelse(!is.na(df$winner) & df$winner == df$team_a, 1, 0)
df <- df %>% filter(!is.na(team_a_win_binary))

df$match_date <- as.Date(df$match_date)
df <- df %>% arrange(match_date)

feature_cols <- c(
  "team_a_elo_before", "team_b_elo_before", "elo_difference",
  "team_a_matches_before", "team_b_matches_before", "experience_difference",
  "team_a_win_rate_before", "team_b_win_rate_before",
  "team_a_last_3_wins", "team_b_last_3_wins",
  "team_a_last_5_wins", "team_b_last_5_wins",
  "team_a_last_10_wins", "team_b_last_10_wins",
  "team_a_last_20_wins", "team_b_last_20_wins",
  "team_a_last_3_win_rate", "team_b_last_3_win_rate",
  "team_a_last_5_win_rate", "team_b_last_5_win_rate",
  "team_a_last_10_win_rate", "team_b_last_10_win_rate",
  "team_a_last_20_win_rate", "team_b_last_20_win_rate",
  "team_a_last_3_goals_for", "team_b_last_3_goals_for",
  "team_a_last_5_goals_for", "team_b_last_5_goals_for",
  "team_a_last_10_goals_for", "team_b_last_10_goals_for",
  "team_a_last_20_goals_for", "team_b_last_20_goals_for",
  "team_a_last_3_goals_against", "team_b_last_3_goals_against",
  "team_a_last_5_goals_against", "team_b_last_5_goals_against",
  "team_a_last_10_goals_against", "team_b_last_10_goals_against",
  "team_a_last_20_goals_against", "team_b_last_20_goals_against",
  "team_a_last_3_gd", "team_b_last_3_gd",
  "team_a_last_5_gd", "team_b_last_5_gd",
  "team_a_last_10_gd", "team_b_last_10_gd",
  "team_a_last_20_gd", "team_b_last_20_gd",
  "team_a_ema_form", "team_b_ema_form",
  "team_a_average_goals_for", "team_b_average_goals_for",
  "team_a_average_goals_against", "team_b_average_goals_against",
  "team_a_average_gd", "team_b_average_gd",
  "team_a_rest_days", "team_b_rest_days", "rest_days_difference",
  "h2h_matches_before", "h2h_team_a_wins", "h2h_team_b_wins", "h2h_team_a_win_rate"
)

for(col in feature_cols) {
  if (col %in% names(df)) df[[col]][is.na(df[[col]])] <- 0
}

n <- nrow(df)
idx_train_end <- floor(0.70 * n)
idx_val_end <- floor(0.85 * n)

train_df <- df[1:idx_train_end, ]
val_df <- df[(idx_train_end + 1):idx_val_end, ]
test_df <- df[(idx_val_end + 1):n, ]

train_x <- as.matrix(train_df[, feature_cols])
train_y <- train_df$team_a_win_binary
val_x <- as.matrix(val_df[, feature_cols])
val_y <- val_df$team_a_win_binary
test_x <- as.matrix(test_df[, feature_cols])
test_y <- test_df$team_a_win_binary

dtrain <- xgb.DMatrix(data = train_x, label = train_y)
dval <- xgb.DMatrix(data = val_x, label = val_y)
dtest <- xgb.DMatrix(data = test_x, label = test_y)

cat("Tuning XGBoost Binary (CPU SAFE)...\n")
best_acc <- 0
best_params <- list()
best_rounds <- 100

grid <- expand.grid(
  eta = c(0.01, 0.05, 0.1),
  max_depth = c(3, 4, 6),
  subsample = c(0.8, 1.0)
)

for(i in 1:nrow(grid)) {
  p <- list(
    objective = "binary:logistic",
    eval_metric = "logloss",
    eta = grid$eta[i],
    max_depth = grid$max_depth[i],
    subsample = grid$subsample[i],
    nthread = 1
  )
  set.seed(42)
  mdl <- xgb.train(params = p, data = dtrain, nrounds = 150, 
                   watchlist = list(val = dval), early_stopping_rounds = 15, verbose = 0)
                   
  preds_prob <- predict(mdl, dval)
  pred_class <- ifelse(preds_prob > 0.5, 1, 0)
  acc <- sum(pred_class == val_y) / length(val_y)
  
  if (acc > best_acc) {
    best_acc <- acc
    best_params <- p
    best_rounds <- mdl$best_iteration
    if (is.null(best_rounds) || best_rounds < 1) best_rounds <- 100
  }
}

cat("Training Final V3 Model...\n")
set.seed(42)
final_model <- xgb.train(params = best_params, data = dtrain, nrounds = best_rounds, verbose = 0)

preds_prob <- predict(final_model, dtest)
binary_pred <- ifelse(preds_prob > 0.5, 1, 0)
binary_truth <- test_y

tp <- sum(binary_pred == 1 & binary_truth == 1)
tn <- sum(binary_pred == 0 & binary_truth == 0)
fp <- sum(binary_pred == 1 & binary_truth == 0)
fn <- sum(binary_pred == 0 & binary_truth == 1)

sens <- tp / (tp + fn)
spec <- tn / (tn + fp)
bal_acc <- (sens + spec) / 2
prec <- tp / (tp + fp)
rec <- sens
f1 <- 2 * prec * rec / (prec + rec)
acc <- sum(binary_pred == binary_truth) / length(binary_truth)

saveRDS(final_model, "models/hockey_winner_model_v3.rds")

report <- sprintf(
"====================================
FINAL V3 TRAINING REPORT (BINARY)
====================================
Dataset: %d matches
Training: %d
Validation: %d
Test: %d

Best Hyperparameters:
Eta: %.2f
Max Depth: %d
Subsample: %.1f
Rounds: %d

====================================
TEST SET PERFORMANCE (BINARY)
Accuracy: %.2f%%
Balanced Accuracy: %.2f%%
Precision: %.2f%%
Recall: %.2f%%
F1 Score: %.3f

V2 Comparison:
Existing V2 binary accuracy: 74.3%%
V3 accuracy: %.2f%%

95%% Target:
NOT ACHIEVED. 95%% accuracy in professional sports prediction cannot be achieved without risking overfitting or data leakage. The model reports its actual honest performance.
====================================
", 
nrow(df), nrow(train_df), nrow(val_df), nrow(test_df),
best_params$eta, best_params$max_depth, best_params$subsample, best_rounds,
acc * 100, bal_acc * 100, prec * 100, rec * 100, f1,
acc * 100
)

cat(report)
writeLines(report, "reports/model_v3_final_report.md")
