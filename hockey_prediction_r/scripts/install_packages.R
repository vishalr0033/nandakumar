# scripts/install_packages.R

cat("========================================\n")
cat("INSTALLING REQUIRED PACKAGES\n")
cat("========================================\n")

# Define the required packages
required_packages <- c(
  "readxl",
  "writexl",
  "dplyr",
  "tidyr",
  "stringr",
  "lubridate",
  "ggplot2",
  "caret",
  "randomForest",
  "xgboost",
  "ranger",
  "pROC",
  "yardstick",
  "jsonlite",
  "shiny"
)

# Function to check and install missing packages
install_if_missing <- function(packages) {
  missing_packages <- packages[!(packages %in% installed.packages()[,"Package"])]
  
  if (length(missing_packages) > 0) {
    cat(sprintf("Found %d missing packages. Installing...\n", length(missing_packages)))
    for (pkg in missing_packages) {
      cat(sprintf("Installing %s...\n", pkg))
      # Install securely without compiling from source if possible on Windows
      install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
    }
    
    # Re-verify
    still_missing <- missing_packages[!(missing_packages %in% installed.packages()[,"Package"])]
    if (length(still_missing) > 0) {
      stop(sprintf("ERROR: Failed to install packages: %s", paste(still_missing, collapse = ", ")))
    }
  } else {
    cat("All required packages are already installed.\n")
  }
}

# Run the installation
tryCatch({
  install_if_missing(required_packages)
  cat("Package installation completed successfully.\n")
}, error = function(e) {
  cat(e$message, "\n")
  quit(status = 1)
})
