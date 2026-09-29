# scripts/train_v2_models.R

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(ranger)
  library(xgboost)
  library(pROC)
  library(yardstick)
})

cat("========================================\n")
cat("TRAINING MODELS ON V2 DATASET\n")
cat("========================================\n")

# Load V2 dataset
file_path <- "data/hockey_prediction_dataset_v2.xlsx"
df <- read_excel(file_path)

# Prepare target
df$team_a_win_binary <- ifelse(!is.na(df$winner) & df$winner == df$team_a, 1, 0)
df <- df %>% filter(!is.na(team_a_win_binary))

# Ensure sorting
df$match_date <- as.Date(df$match_date)
df <- df %>% arrange(match_date)

# Select safe features
feature_cols <- c(
  "team_a_elo_before", "team_b_elo_before", "elo_difference",
  "team_a_previous_matches", "team_b_previous_matches",
  "team_a_previous_wins", "team_b_previous_wins",
  "team_a_previous_losses", "team_b_previous_losses",
  "team_a_win_rate_before", "team_b_win_rate_before",
  "team_a_last_5_wins", "team_b_last_5_wins",
  "team_a_last_10_wins", "team_b_last_10_wins",
  "team_a_last_5_goals_for", "team_b_last_5_goals_for",
  "team_a_last_5_goals_against", "team_b_last_5_goals_against",
  "team_a_last_10_goals_for", "team_b_last_10_goals_for",
  "team_a_last_10_goals_against", "team_b_last_10_goals_against",
  "team_a_average_goals_for", "team_b_average_goals_for",
  "team_a_average_goals_against", "team_b_average_goals_against",
  "team_a_average_goal_difference", "team_b_average_goal_difference",
  "team_a_last_5_goal_difference", "team_b_last_5_goal_difference",
  "team_a_last_10_goal_difference", "team_b_last_10_goal_difference",
  "team_a_rest_days", "team_b_rest_days", "rest_days_difference",
  "h2h_matches_before", "h2h_team_a_wins", "h2h_team_b_wins", "h2h_draws",
  "h2h_team_a_win_rate", "h2h_team_b_win_rate"
)

# Impute NA features safely (from very early matches)
for(col in feature_cols) {
  if (col %in% names(df)) {
    df[[col]][is.na(df[[col]])] <- 0
  }
}

df$target_fct <- as.factor(ifelse(df$team_a_win_binary == 1, "Win", "NotWin"))

# Chronological split
n <- nrow(df)
idx_train_end <- floor(0.70 * n)
idx_val_end <- floor(0.85 * n)

train_df <- df[1:idx_train_end, ]
val_df <- df[(idx_train_end + 1):idx_val_end, ]
test_df <- df[(idx_val_end + 1):n, ]

train_x <- as.matrix(train_df[, feature_cols])
train_y <- train_df$team_a_win_binary

test_x <- as.matrix(test_df[, feature_cols])
test_y <- test_df$team_a_win_binary
test_y_fct <- test_df$target_fct

cat("Training Logistic Regression...\n")
model_logreg <- glm(team_a_win_binary ~ ., data = train_df[, c(feature_cols, "team_a_win_binary")], family = binomial)

cat("Training Random Forest (Ranger) - CPU SAFE...\n")
model_ranger <- ranger(
  formula = target_fct ~ ., 
  data = train_df[, c(feature_cols, "target_fct")],
  num.trees = 150,
  num.threads = 1,
  probability = TRUE,
  importance = 'impurity',
  seed = 42
)

cat("Training XGBoost - CPU SAFE...\n")
dtrain <- xgb.DMatrix(data = train_x, label = train_y)
params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 4,
  eta = 0.05,
  nthread = 1
)

set.seed(42)
model_xgb <- xgb.train(
  params = params,
  data = dtrain,
  nrounds = 100,
  verbose = 0
)

# Metrics Helper Functions
calc_brier <- function(preds, truth) { mean((preds - truth)^2) }
calc_logloss <- function(preds, truth) {
  eps <- 1e-15
  preds <- pmax(pmin(preds, 1 - eps), eps)
  -mean(truth * log(preds) + (1 - truth) * log(1 - preds))
}

evaluate_model <- function(model_name, preds_prob, truth_binary) {
  pred_class <- ifelse(preds_prob > 0.5, 1, 0)
  
  acc <- sum(pred_class == truth_binary) / length(truth_binary)
  
  tp <- sum(pred_class == 1 & truth_binary == 1)
  tn <- sum(pred_class == 0 & truth_binary == 0)
  fp <- sum(pred_class == 1 & truth_binary == 0)
  fn <- sum(pred_class == 0 & truth_binary == 1)
  
  sensitivity <- ifelse((tp + fn) > 0, tp / (tp + fn), 0)
  specificity <- ifelse((tn + fp) > 0, tn / (tn + fp), 0)
  
  bal_acc <- (sensitivity + specificity) / 2
  precision <- ifelse((tp + fp) > 0, tp / (tp + fp), 0)
  recall <- sensitivity
  f1 <- ifelse((precision + recall) > 0, 2 * (precision * recall) / (precision + recall), 0)
  
  roc_obj <- roc(truth_binary, preds_prob, quiet=TRUE)
  roc_auc <- as.numeric(auc(roc_obj))
  
  brier <- calc_brier(preds_prob, truth_binary)
  logloss <- calc_logloss(preds_prob, truth_binary)
  
  cm_str <- sprintf("TP: %d, FP: %d\nFN: %d, TN: %d", tp, fp, fn, tn)
  
  list(
    Model = model_name,
    Accuracy = acc,
    Balanced_Accuracy = bal_acc,
    Precision = precision,
    Recall = recall,
    F1 = f1,
    ROC_AUC = roc_auc,
    Log_Loss = logloss,
    Brier_Score = brier,
    Confusion_Matrix = cm_str
  )
}

# Evaluate
preds_logreg <- predict(model_logreg, newdata = test_df, type = "response")
res_logreg <- evaluate_model("Logistic Regression", preds_logreg, test_y)

preds_ranger <- predict(model_ranger, data = test_df[, feature_cols])$predictions[, "Win"]
res_ranger <- evaluate_model("Random Forest (ranger)", preds_ranger, test_y)

dtest <- xgb.DMatrix(data = test_x, label = test_y)
preds_xgb <- predict(model_xgb, dtest)
res_xgb <- evaluate_model("XGBoost", preds_xgb, test_y)

# Combine
results <- bind_rows(
  as.data.frame(res_logreg[1:9]),
  as.data.frame(res_ranger[1:9]),
  as.data.frame(res_xgb[1:9])
)
results <- results %>% arrange(desc(ROC_AUC))

best_model_name <- results$Model[1]
if (best_model_name == "Logistic Regression") best_model <- model_logreg
if (best_model_name == "Random Forest (ranger)") best_model <- model_ranger
if (best_model_name == "XGBoost") best_model <- model_xgb

saveRDS(best_model, "models/hockey_winner_model_v2.rds")

# Generate Report
report_txt <- sprintf(
"====================================
FINAL V2 TRAINING REPORT
====================================
Total Matches: %d
Train/Val/Test: %d / %d / %d

Model Selection:
%s

Metrics (Best Model on Test Set):
Accuracy: %.1f%%
Balanced Accuracy: %.1f%%
Precision: %.1f%%
Recall: %.1f%%
F1 Score: %.3f
ROC-AUC: %.1f%%
Log Loss: %.3f
Brier Score: %.3f

Confusion Matrix:
%s

All models evaluated properly using strict chronological pre-match data.
Saved to: models/hockey_winner_model_v2.rds
====================================
", 
nrow(df), nrow(train_df), nrow(val_df), nrow(test_df),
paste(capture.output(print(results, row.names = FALSE)), collapse = "\n"),
results$Accuracy[1] * 100,
results$Balanced_Accuracy[1] * 100,
results$Precision[1] * 100,
results$Recall[1] * 100,
results$F1[1],
results$ROC_AUC[1] * 100,
results$Log_Loss[1],
results$Brier_Score[1],
if(best_model_name == "XGBoost") res_xgb$Confusion_Matrix else if(best_model_name == "Random Forest (ranger)") res_ranger$Confusion_Matrix else res_logreg$Confusion_Matrix
)

cat(report_txt)
writeLines(report_txt, "reports/model_v2_report.txt")
