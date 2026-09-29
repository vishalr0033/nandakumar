# scripts/04_evaluate_models.R

suppressPackageStartupMessages({
  library(dplyr)
  library(pROC)
  library(yardstick)
  library(xgboost)
  library(ranger)
})

cat("========================================\n")
cat("EVALUATING MODELS\n")
cat("========================================\n")

test_df <- readRDS("data/test_df.rds")

# Load models
model_logreg <- readRDS("models/model_logreg.rds")
model_ranger <- readRDS("models/model_ranger.rds")
model_xgb <- readRDS("models/model_xgb.rds")

feature_cols <- c(
  "elo_difference", "team_a_elo", "team_b_elo",
  "team_a_win_rate", "team_b_win_rate",
  "team_a_form_5", "team_b_form_5",
  "team_a_form_10", "team_b_form_10",
  "team_a_avg_gd", "team_b_avg_gd",
  "team_a_recent_gd", "team_b_recent_gd",
  "team_a_h2h_win_rate", "team_a_matches", "team_b_matches", "h2h_matches"
)
test_x <- as.matrix(test_df[, feature_cols])
test_y <- test_df$team_a_win_binary

# Helper function to calculate Brier Score
calc_brier <- function(preds, truth) {
  mean((preds - truth)^2)
}

# Helper function to calculate Log Loss
calc_logloss <- function(preds, truth) {
  eps <- 1e-15
  preds <- pmax(pmin(preds, 1 - eps), eps)
  -mean(truth * log(preds) + (1 - truth) * log(1 - preds))
}

results <- list()

# Evaluate LogReg
preds_logreg <- predict(model_logreg, newdata = test_df, type = "response")
roc_logreg <- roc(test_y, preds_logreg, quiet=TRUE)
auc_logreg <- auc(roc_logreg)
pred_class_logreg <- ifelse(preds_logreg > 0.5, 1, 0)
acc_logreg <- mean(pred_class_logreg == test_y)

results[[1]] <- data.frame(
  Model = "Logistic Regression",
  Accuracy = acc_logreg,
  ROC_AUC = as.numeric(auc_logreg),
  Brier_Score = calc_brier(preds_logreg, test_y),
  Log_Loss = calc_logloss(preds_logreg, test_y)
)

# Evaluate Ranger
preds_ranger <- predict(model_ranger, data = test_df[, feature_cols])$predictions[, "Win"]
roc_ranger <- roc(test_y, preds_ranger, quiet=TRUE)
auc_ranger <- auc(roc_ranger)
pred_class_ranger <- ifelse(preds_ranger > 0.5, 1, 0)
acc_ranger <- mean(pred_class_ranger == test_y)

results[[2]] <- data.frame(
  Model = "Random Forest (ranger)",
  Accuracy = acc_ranger,
  ROC_AUC = as.numeric(auc_ranger),
  Brier_Score = calc_brier(preds_ranger, test_y),
  Log_Loss = calc_logloss(preds_ranger, test_y)
)

# Evaluate XGBoost
dtest <- xgb.DMatrix(data = test_x, label = test_y)
preds_xgb <- predict(model_xgb, dtest)
roc_xgb <- roc(test_y, preds_xgb, quiet=TRUE)
auc_xgb <- auc(roc_xgb)
pred_class_xgb <- ifelse(preds_xgb > 0.5, 1, 0)
acc_xgb <- mean(pred_class_xgb == test_y)

results[[3]] <- data.frame(
  Model = "XGBoost",
  Accuracy = acc_xgb,
  ROC_AUC = as.numeric(auc_xgb),
  Brier_Score = calc_brier(preds_xgb, test_y),
  Log_Loss = calc_logloss(preds_xgb, test_y)
)

res_df <- bind_rows(results)
res_df <- res_df %>% arrange(desc(ROC_AUC))

write.csv(res_df, "reports/model_comparison.csv", row.names = FALSE)

print(res_df)
cat("Evaluation complete. Results saved to reports/model_comparison.csv\n")
