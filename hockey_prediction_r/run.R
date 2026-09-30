# hockey_prediction_r/run.R
# Run this file to start the Shiny App immediately
if (!requireNamespace("shiny", quietly = TRUE)) install.packages("shiny")
shiny::runApp("app", host = "127.0.0.1", port = 3838, launch.browser = TRUE)
