# scripts/05_save_model.R

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

cat("========================================\n")
cat("SAVING BEST MODEL\n")
cat("========================================\n")

res_df <- read.csv("reports/model_comparison.csv")
best_model_name <- res_df$Model[1]
cat(sprintf("Best model based on ROC-AUC is: %s\n", best_model_name))

if (best_model_name == "Logistic Regression") {
  best_model <- readRDS("models/model_logreg.rds")
} else if (best_model_name == "Random Forest (ranger)") {
  best_model <- readRDS("models/model_ranger.rds")
} else {
  best_model <- readRDS("models/model_xgb.rds")
}

saveRDS(best_model, "models/hockey_winner_model.rds")
saveRDS(best_model, "models/model_v1.rds")

# Generate Metadata
test_df <- readRDS("data/test_df.rds")
train_df <- readRDS("data/train_df.rds")
val_df <- readRDS("data/val_df.rds")

feature_cols <- c(
  "elo_difference", "team_a_elo", "team_b_elo",
  "team_a_win_rate", "team_b_win_rate",
  "team_a_form_5", "team_b_form_5",
  "team_a_form_10", "team_b_form_10",
  "team_a_avg_gd", "team_b_avg_gd",
  "team_a_recent_gd", "team_b_recent_gd",
  "team_a_h2h_win_rate", "team_a_matches", "team_b_matches", "h2h_matches"
)

meta <- list(
  model_type = best_model_name,
  training_date = as.character(Sys.Date()),
  feature_names = feature_cols,
  training_date_range = paste(min(train_df$match_date), "to", max(train_df$match_date)),
  validation_date_range = paste(min(val_df$match_date), "to", max(val_df$match_date)),
  test_date_range = paste(min(test_df$match_date), "to", max(test_df$match_date)),
  metrics = as.list(res_df[1, ]),
  dataset_version = "hockey_matches_final_enriched.xlsx"
)

write_json(meta, "models/model_metadata.json", pretty = TRUE)

# Generate Model V1 Report
report_txt <- sprintf(
"====================================
TRAINING COMPLETE
====================================
Dataset:
%s matches

Training matches:
%s

Validation matches:
%s

Test matches:
%s

Best model:
%s

Test accuracy:
%.1f%%

ROC-AUC:
%.1f%%

Log loss:
%.3f

Brier score:
%.3f

CPU threads:
1

GPU:
NOT USED

Model saved:
models/hockey_winner_model.rds
models/model_v1.rds
====================================
", 
  nrow(train_df) + nrow(val_df) + nrow(test_df),
  nrow(train_df), nrow(val_df), nrow(test_df),
  best_model_name,
  res_df$Accuracy[1] * 100,
  res_df$ROC_AUC[1] * 100,
  res_df$Log_Loss[1],
  res_df$Brier_Score[1]
)

cat(report_txt)
writeLines(report_txt, "reports/model_v1_report.txt")

# Generate Reproducibility Report
repro_txt <- sprintf(
"REPRODUCIBILITY LOG
===================
Date: %s
R Version: %s
Dataset: hockey_matches_final_enriched.xlsx
Total Rows: %d
Seed: 42
Model Type: %s
Features: %s
", Sys.time(), R.version.string, nrow(train_df) + nrow(val_df) + nrow(test_df), best_model_name, paste(feature_cols, collapse=", "))

writeLines(repro_txt, "reports/reproducibility.txt")
