# scripts/convert_data_rds.R
suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
})

cat("Reading hockey_prediction_dataset_v4.xlsx...\n")
df <- read_excel("data/hockey_prediction_dataset_v4.xlsx")
cat("Saving hockey_prediction_dataset_v4.rds...\n")
saveRDS(df, "data/hockey_prediction_dataset_v4.rds")
cat("Done! Dataset has", nrow(df), "rows and", ncol(df), "columns.\n")
