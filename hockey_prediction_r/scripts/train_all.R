# scripts/train_all.R

cat("Starting Full Training Pipeline\n")

# source("scripts/install_packages.R")
source("scripts/01_data_audit.R")
source("scripts/02_feature_engineering.R")
source("scripts/03_train_models.R")
source("scripts/04_evaluate_models.R")
source("scripts/05_save_model.R")

cat("Pipeline completed successfully.\n")
