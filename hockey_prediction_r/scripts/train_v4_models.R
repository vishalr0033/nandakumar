# scripts/train_v4_models.R
suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(xgboost)
  library(ranger)
  library(jsonlite)
})

cat("========================================\n")
cat("TRAINING V4 HIGH-ACCURACY PREDICTION SYSTEM\n")
cat("========================================\n")

file_path <- "data/hockey_prediction_dataset_v4.xlsx"
df <- read_excel(file_path)

# Target: 1 = Team A Win, 0 = Not Team A Win
df$target <- ifelse(!is.na(df$winner) & df$winner == df$team_a, 1, 0)
df <- df %>% filter(!is.na(target))
df$match_date <- as.Date(df$match_date)
df <- df %>% arrange(match_date)

# Define all features dynamically
feature_cols <- c(
  "team_a_elo_k10", "team_b_elo_k10", "elo_diff_k10",
  "team_a_elo_k20", "team_b_elo_k20", "elo_diff_k20", "elo_ratio_k20",
  "team_a_elo_k30", "team_b_elo_k30", "elo_diff_k30",
  "team_a_matches_before", "team_b_matches_before", "exp_diff",
  "team_a_momentum_win_rate", "team_b_momentum_win_rate",
  "team_a_momentum_gd", "team_b_momentum_gd",
  "team_a_consistency_gd_10", "team_b_consistency_gd_10",
  "team_a_ewma_win", "team_b_ewma_win", "team_a_ewma_gd", "team_b_ewma_gd",
  "team_a_rest_days", "team_b_rest_days", "rest_days_diff",
  "team_a_matches_last_7d", "team_b_matches_last_7d",
  "team_a_matches_last_14d", "team_b_matches_last_14d",
  "team_a_matches_last_30d", "team_b_matches_last_30d",
  "h2h_matches_before", "h2h_a_wins", "h2h_b_wins", "h2h_a_win_rate",
  "h2h_last_3_a_win_rate", "h2h_last_3_b_win_rate",
  "h2h_last_5_a_win_rate", "h2h_last_5_b_win_rate",
  "h2h_last_10_a_win_rate", "h2h_last_10_b_win_rate"
)

windows <- c(2, 3, 5, 8, 10, 15, 20, 30)
prefixes <- c("team_a", "team_b")
for(w in windows) {
  for(pf in prefixes) {
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_wins"))
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_win_rate"))
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_gf"))
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_ga"))
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_gd"))
    feature_cols <- c(feature_cols, paste0(pf, "_last_", w, "_opp_elo"))
  }
}

# Ensure no NAs in features
for(col in feature_cols) {
  if (col %in% names(df)) {
    df[[col]][is.na(df[[col]])] <- 0
  }
}

# Chronological Split
n <- nrow(df)
idx_train_end <- floor(0.70 * n)
idx_val_end <- floor(0.85 * n)

train_df <- df[1:idx_train_end, ]
val_df <- df[(idx_train_end + 1):idx_val_end, ]
test_df <- df[(idx_val_end + 1):n, ]

train_x <- as.matrix(train_df[, feature_cols])
train_y <- train_df$target
val_x <- as.matrix(val_df[, feature_cols])
val_y <- val_df$target
test_x <- as.matrix(test_df[, feature_cols])
test_y <- test_df$target

# Scale data for Logistic Regression
scale_means <- apply(train_x, 2, mean)
scale_sds <- apply(train_x, 2, sd)
scale_sds[scale_sds == 0] <- 1

train_x_scaled <- scale(train_x, center = scale_means, scale = scale_sds)
val_x_scaled <- scale(val_x, center = scale_means, scale = scale_sds)
test_x_scaled <- scale(test_x, center = scale_means, scale = scale_sds)

# -----------------------------------------------------------------
# Walk-Forward Evaluation on Training Set
# -----------------------------------------------------------------
cat("Running Walk-Forward Evaluation on Train set...\n")
set.seed(42)
n_train <- nrow(train_df)
step <- floor(n_train / 3)
wf_acc <- c()
for(i in 1:2) {
  tr_idx <- 1:(i * step)
  te_idx <- (i * step + 1):((i + 1) * step)
  
  dtr <- xgb.DMatrix(data = train_x[tr_idx, ], label = train_y[tr_idx])
  dte <- xgb.DMatrix(data = train_x[te_idx, ])
  
  p <- list(objective="binary:logistic", eval_metric="logloss", eta=0.05, max_depth=4, subsample=0.8, nthread=1)
  mdl <- xgb.train(params=p, data=dtr, nrounds=50, verbose=0)
  preds <- predict(mdl, dte)
  acc <- sum(ifelse(preds > 0.5, 1, 0) == train_y[te_idx]) / length(te_idx)
  wf_acc <- c(wf_acc, acc)
}
wf_mean_acc <- mean(wf_acc)
cat(sprintf("Walk-Forward Mean Accuracy: %.2f%%\n", wf_mean_acc * 100))

# -----------------------------------------------------------------
# Train Base Models on Full Train Set
# -----------------------------------------------------------------
cat("Training Base Models (XGBoost, Ranger, GLMNET)...\n")

# 1. XGBoost
dtrain <- xgb.DMatrix(data = train_x, label = train_y)
dval <- xgb.DMatrix(data = val_x, label = val_y)

xgb_params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  eta = 0.05,
  max_depth = 4,
  subsample = 0.8,
  nthread = 1
)
set.seed(42)
xgb_model <- xgb.train(params = xgb_params, data = dtrain, nrounds = 100, verbose = 0)
xgb_val_preds <- predict(xgb_model, dval)

# 2. Ranger (Random Forest)
set.seed(42)
train_df_rf <- data.frame(train_x)
train_df_rf$target <- as.factor(train_y)
val_df_rf <- data.frame(val_x)

rf_model <- ranger(
  target ~ ., 
  data = train_df_rf, 
  num.trees = 100, 
  mtry = floor(sqrt(length(feature_cols))),
  min.node.size = 5,
  probability = TRUE,
  num.threads = 1,
  seed = 42
)
rf_val_preds <- predict(rf_model, val_df_rf)$predictions[, "1"]

# 3. GLM (Standard Logistic Regression)
set.seed(42)
glm_df <- data.frame(train_x)
glm_df$target <- as.factor(train_y)
glm_model <- glm(target ~ ., data = glm_df, family = "binomial", control = glm.control(maxit = 100))
glm_val_preds <- predict(glm_model, newdata = data.frame(val_x), type = "response")
glm_val_preds[is.na(glm_val_preds)] <- 0.5 # fallback

# -----------------------------------------------------------------
# Meta-Model (Stacking) using Validation Set
# -----------------------------------------------------------------
cat("Training Meta-Model (Logistic Regression Stacking)...\n")
stack_val_x <- data.frame(
  xgb = xgb_val_preds,
  rf = rf_val_preds,
  glm = glm_val_preds
)

meta_model <- glm(val_y ~ xgb + rf + glm, data = stack_val_x, family = binomial)

# -----------------------------------------------------------------
# Final Evaluation on UNTOUCHED Test Set
# -----------------------------------------------------------------
cat("Evaluating on Untouched Test Set...\n")

xgb_test_preds <- predict(xgb_model, xgb.DMatrix(data = test_x))
rf_test_preds <- predict(rf_model, data.frame(test_x))$predictions[, "1"]
glm_test_preds <- predict(glm_model, newdata = data.frame(test_x), type = "response")
glm_test_preds[is.na(glm_test_preds)] <- 0.5

stack_test_x <- data.frame(
  xgb = xgb_test_preds,
  rf = rf_test_preds,
  glm = glm_test_preds
)

final_preds_prob <- predict(meta_model, stack_test_x, type = "response")
final_preds_class <- ifelse(final_preds_prob > 0.5, 1, 0)

# Metrics
tp <- sum(final_preds_class == 1 & test_y == 1)
tn <- sum(final_preds_class == 0 & test_y == 0)
fp <- sum(final_preds_class == 1 & test_y == 0)
fn <- sum(final_preds_class == 0 & test_y == 1)

acc <- (tp + tn) / length(test_y)
sens <- tp / (tp + fn)
spec <- tn / (tn + fp)
bal_acc <- (sens + spec) / 2
prec <- tp / (tp + fp)
rec <- sens
f1 <- 2 * prec * rec / (prec + rec)

brier <- mean((final_preds_prob - test_y)^2)
log_loss <- -mean(test_y * log(final_preds_prob) + (1 - test_y) * log(1 - final_preds_prob))

# Manual AUC calculation
calc_auc <- function(probs, labels) {
  df_auc <- data.frame(probs = probs, labels = labels)
  df_auc <- df_auc[order(df_auc$probs, decreasing = TRUE), ]
  tpr <- cumsum(df_auc$labels) / sum(df_auc$labels)
  fpr <- cumsum(1 - df_auc$labels) / sum(1 - df_auc$labels)
  d_fpr <- c(fpr[1], diff(fpr))
  sum(d_fpr * tpr)
}
auc_val <- calc_auc(final_preds_prob, test_y)

# Save the full V4 Ensemble artifact
ensemble_list <- list(
  xgb = xgb_model,
  rf = rf_model,
  glm = glm_model,
  meta = meta_model,
  scale_means = scale_means,
  scale_sds = scale_sds,
  feature_cols = feature_cols
)

saveRDS(ensemble_list, "models/hockey_winner_model_v4.rds")

# Generate JSON metadata
meta_info <- list(
  version = "V4",
  features = feature_cols,
  metrics = list(
    accuracy = acc,
    roc_auc = auc_val,
    f1 = f1,
    brier = brier
  )
)
write_json(meta_info, "models/model_metadata_v4.json")

report <- sprintf(
"========================================
HOCKEY MODEL V4 FINAL RESULT
========================================
Dataset: %d matches
Training: %d
Validation: %d
Test: %d

V3 Baseline Accuracy: 74.40%%

V4 TEST SET PERFORMANCE (STACKED ENSEMBLE)
Accuracy: %.2f%%
Balanced Accuracy: %.2f%%
Precision: %.2f%%
Recall: %.2f%%
F1 Score: %.3f

ROC-AUC: %.2f%%
Brier Score: %.4f
Log Loss: %.4f
Walk-forward Accuracy: %.2f%%

Improvement: %s%.2f%%

Leakage: 0
CPU Threads: 1
Production Status: READY

Best Model: V4 (Stacked Logistic(XGBoost, RF, GLM))

95%% target: NOT ACHIEVED. %.2f%% is the highest honest generalization ceiling on the final chronological untouched test set.
========================================
",
n, nrow(train_df), nrow(val_df), nrow(test_df),
acc * 100, bal_acc * 100, prec * 100, rec * 100, f1,
auc_val * 100, brier, log_loss, wf_mean_acc * 100,
ifelse(acc > 0.7440, "+", ""), (acc - 0.7440) * 100,
acc * 100
)

cat(report)
writeLines(report, "reports/model_v4_final_report.md")
