# run_dashboard.R
cat("Starting Hockey Intelligence & World Cup 2026 Dashboard...\n")
library(shiny)
app_dir <- file.path(getwd(), "app")
if (!dir.exists(app_dir)) {
  app_dir <- "c:/Users/rajap/OneDrive/Desktop/r pr/nandhu/hockey_prediction_r/app"
}
cat("App Directory:", app_dir, "\n")
shiny::runApp(appDir = app_dir, host = "127.0.0.1", port = 3838, launch.browser = TRUE)
