# app/app.R
library(shiny)
library(xgboost)
library(dplyr)
library(jsonlite)
library(lubridate)
library(readxl)
library(ranger)
library(bslib)
library(htmltools)

# Load data and model globally
model_path <- "../models/hockey_winner_model_v4.rds"
data_path <- "../data/hockey_prediction_dataset_v4.xlsx"

if (!file.exists(model_path) || !file.exists(data_path)) {
  stop("Ensure hockey_winner_model_v4.rds and the dataset exist in the relative paths.")
}

final_model <- readRDS(model_path)
df <- read_excel(data_path)

teams <- sort(unique(c(df$team_a, df$team_b)))

# --- Helper Function to Predict and Generate UI ---
generate_prediction_ui <- function(ta, tb, m_date, is_final = FALSE) {
    if (ta == tb) {
      return(h3("Error: Select two different teams.", style="color:red;"))
    }
    
    df_ta <- df %>% filter((team_a == ta | team_b == ta) & as.Date(match_date) < m_date) %>% arrange(match_date)
    df_tb <- df %>% filter((team_a == tb | team_b == tb) & as.Date(match_date) < m_date) %>% arrange(match_date)
    
    if (nrow(df_ta) == 0 || nrow(df_tb) == 0) {
      return(h3("Error: Insufficient historical data before this date.", style="color:red;"))
    }
    
    last_ta <- df_ta %>% slice(n())
    last_tb <- df_tb %>% slice(n())
    
    feature_cols <- final_model$feature_cols
    feat_matrix <- data.frame(matrix(0, nrow = 1, ncol = length(feature_cols)))
    colnames(feat_matrix) <- feature_cols
    
    for (col in feature_cols) {
      if (startsWith(col, "team_a_")) {
         alt_col <- gsub("team_a_", "team_b_", col)
         feat_matrix[[col]] <- ifelse(last_ta$team_a == ta, last_ta[[col]], last_ta[[alt_col]])
      } else if (startsWith(col, "team_b_")) {
         alt_col <- gsub("team_b_", "team_a_", col)
         feat_matrix[[col]] <- ifelse(last_tb$team_a == tb, last_tb[[alt_col]], last_tb[[col]])
      }
    }
    
    feat_matrix$elo_diff_k10 <- feat_matrix$team_a_elo_k10 - feat_matrix$team_b_elo_k10
    feat_matrix$elo_diff_k20 <- feat_matrix$team_a_elo_k20 - feat_matrix$team_b_elo_k20
    feat_matrix$elo_diff_k30 <- feat_matrix$team_a_elo_k30 - feat_matrix$team_b_elo_k30
    feat_matrix$elo_ratio_k20 <- feat_matrix$team_a_elo_k20 / ifelse(feat_matrix$team_b_elo_k20 > 0, feat_matrix$team_b_elo_k20, 1)
    feat_matrix$exp_diff <- feat_matrix$team_a_matches_before - feat_matrix$team_b_matches_before
    
    feat_matrix$team_a_rest_days <- as.numeric(m_date - as.Date(last_ta$match_date))
    feat_matrix$team_b_rest_days <- as.numeric(m_date - as.Date(last_tb$match_date))
    feat_matrix$rest_days_diff <- feat_matrix$team_a_rest_days - feat_matrix$team_b_rest_days
    
    feat_matrix$team_a_matches_last_7d <- ifelse(feat_matrix$team_a_rest_days <= 7, last_ta$team_a_matches_last_7d, 0) 
    feat_matrix$team_b_matches_last_7d <- ifelse(feat_matrix$team_b_rest_days <= 7, last_tb$team_b_matches_last_7d, 0)
    feat_matrix$team_a_matches_last_14d <- ifelse(feat_matrix$team_a_rest_days <= 14, last_ta$team_a_matches_last_14d, 0)
    feat_matrix$team_b_matches_last_14d <- ifelse(feat_matrix$team_b_rest_days <= 14, last_tb$team_b_matches_last_14d, 0)
    feat_matrix$team_a_matches_last_30d <- ifelse(feat_matrix$team_a_rest_days <= 30, last_ta$team_a_matches_last_30d, 0)
    feat_matrix$team_b_matches_last_30d <- ifelse(feat_matrix$team_b_rest_days <= 30, last_tb$team_b_matches_last_30d, 0)
    
    df_h2h <- df %>% filter(((team_a == ta & team_b == tb) | (team_a == tb & team_b == ta)) & as.Date(match_date) < m_date) %>% arrange(match_date)
    if (nrow(df_h2h) > 0) {
        last_h2h <- df_h2h %>% slice(n())
        feat_matrix$h2h_matches_before <- last_h2h$h2h_matches_before + 1
        
        ta_wins <- ifelse(last_h2h$team_a == ta, last_h2h$h2h_a_wins, last_h2h$h2h_b_wins)
        tb_wins <- ifelse(last_h2h$team_b == tb, last_h2h$h2h_b_wins, last_h2h$h2h_a_wins)
        
        if (last_h2h$winner == ta && last_h2h$result != "DRAW") ta_wins <- ta_wins + 1
        if (last_h2h$winner == tb && last_h2h$result != "DRAW") tb_wins <- tb_wins + 1
        
        feat_matrix$h2h_a_wins <- ta_wins
        feat_matrix$h2h_b_wins <- tb_wins
        feat_matrix$h2h_a_win_rate <- ta_wins / feat_matrix$h2h_matches_before
        
        feat_matrix$h2h_last_3_a_win_rate <- 0
        feat_matrix$h2h_last_3_b_win_rate <- 0
        feat_matrix$h2h_last_5_a_win_rate <- 0
        feat_matrix$h2h_last_5_b_win_rate <- 0
        feat_matrix$h2h_last_10_a_win_rate <- 0
        feat_matrix$h2h_last_10_b_win_rate <- 0
    } else {
        feat_matrix$h2h_matches_before <- 0
        feat_matrix$h2h_a_wins <- 0
        feat_matrix$h2h_b_wins <- 0
        feat_matrix$h2h_a_win_rate <- 0.0
        feat_matrix$h2h_last_3_a_win_rate <- 0
        feat_matrix$h2h_last_3_b_win_rate <- 0
        feat_matrix$h2h_last_5_a_win_rate <- 0
        feat_matrix$h2h_last_5_b_win_rate <- 0
        feat_matrix$h2h_last_10_a_win_rate <- 0
        feat_matrix$h2h_last_10_b_win_rate <- 0
    }
    
    feat_matrix[is.na(feat_matrix)] <- 0
    test_x_mat <- as.matrix(feat_matrix[, feature_cols])
    
    prob_xgb <- predict(final_model$xgb, xgb.DMatrix(data = test_x_mat))
    prob_rf <- predict(final_model$rf, data.frame(test_x_mat))$predictions[, "1"]
    test_x_scaled <- scale(test_x_mat, center = final_model$scale_means, scale = final_model$scale_sds)
    prob_glm <- predict(final_model$glm, newdata = data.frame(test_x_mat), type = "response")
    if(is.na(prob_glm)) prob_glm <- 0.5
    
    stack_df <- data.frame(xgb = prob_xgb, rf = prob_rf, glm = prob_glm)
    prob_a <- predict(final_model$meta, stack_df, type = "response")
    prob_b <- 1 - prob_a
    
    winner <- ifelse(prob_a > 0.5, ta, tb)
    conf <- ifelse(abs(prob_a - prob_b) > 0.20, "HIGH", ifelse(abs(prob_a - prob_b) > 0.10, "MEDIUM", "LOW"))
    
    # Custom Gold UI if it's the World Cup Final
    if (is_final) {
      main_color_a <- ifelse(winner == ta, "#D97706", "#64748B") # Gold vs Silver
      main_color_b <- ifelse(winner == tb, "#D97706", "#64748B")
      header_bg <- "background: linear-gradient(135deg, #F59E0B 0%, #D97706 100%); color: white;"
      header_title <- h3(icon("trophy"), " 2026 WORLD CUP FINAL CHAMPION", style = "margin: 0; font-weight: bold;")
    } else {
      main_color_a <- "#2563EB"
      main_color_b <- "#EF4444"
      header_bg <- ""
      header_title <- h3("PREDICTION (BINARY MODEL)", style = "margin: 0; font-weight: bold; color: #1E293B;")
    }

    winner_color <- ifelse(is_final, "#D97706", "#2563EB")
    
    ui_out <- tagList(
        fluidRow(
          column(12, 
            card(
              card_header(header_title, style = header_bg),
              card_body(
                h4(strong("Predicted Winner: "), span(winner, style=sprintf("color: %s; font-size: 1.5em; font-weight: bold;", winner_color))),
                if(!is_final) h5(strong("Confidence: "), conf),
                br(),
                tags$div(
                  style = "display: flex; justify-content: space-between; margin-bottom: 5px;",
                  tags$span(strong(ta), style = sprintf("font-size: 1.2em; color: %s;", main_color_a)),
                  tags$span(strong(sprintf("%.1f%%", prob_a * 100)), style = sprintf("font-size: 1.2em; color: %s;", main_color_a))
                ),
                tags$div(
                  class = "progress",
                  style = "height: 25px; margin-bottom: 15px; border-radius: 8px;",
                  tags$div(
                    class = "progress-bar progress-bar-striped progress-bar-animated",
                    style = sprintf("width: %f%%; background-color: %s;", prob_a * 100, main_color_a),
                    sprintf("%.1f%%", prob_a * 100)
                  )
                ),
                tags$div(
                  style = "display: flex; justify-content: space-between; margin-bottom: 5px;",
                  tags$span(strong(tb), style = sprintf("font-size: 1.2em; color: %s;", main_color_b)),
                  tags$span(strong(sprintf("%.1f%%", prob_b * 100)), style = sprintf("font-size: 1.2em; color: %s;", main_color_b))
                ),
                tags$div(
                  class = "progress",
                  style = "height: 25px; margin-bottom: 15px; border-radius: 8px;",
                  tags$div(
                    class = "progress-bar progress-bar-striped progress-bar-animated",
                    style = sprintf("width: %f%%; background-color: %s;", prob_b * 100, main_color_b),
                    sprintf("%.1f%%", prob_b * 100)
                  )
                ),
                p(em("Note: This model is binary and predicts the winner between Team A and Team B. It does not predict draws."), style="color: gray; font-size: 0.9em;")
              )
            )
          )
        ),
        br(),
        fluidRow(
          column(6,
            card(
              card_header(h4("TEAM COMPARISON (ELO)", style = "margin: 0; color: #1E293B;")),
              card_body(
                value_box(
                  title = paste0(ta, " ELO"),
                  value = round(feat_matrix$team_a_elo_k20),
                  showcase = icon("arrow-trend-up"),
                  theme = ifelse(is_final && winner==ta, "warning", "primary") # warning is yellow/gold
                ),
                value_box(
                  title = paste0(tb, " ELO"),
                  value = round(feat_matrix$team_b_elo_k20),
                  showcase = icon("arrow-trend-up"),
                  theme = ifelse(is_final && winner==tb, "warning", "danger")
                )
              )
            )
          ),
          column(6,
            card(
              card_header(h4("RECENT FORM (WIN RATE MOMENTUM)", style = "margin: 0; color: #1E293B;")),
              card_body(
                value_box(
                  title = paste0(ta, " Momentum"),
                  value = round(feat_matrix$team_a_momentum_win_rate, 2),
                  showcase = icon("bolt"),
                  theme = ifelse(is_final && winner==ta, "warning", "primary")
                ),
                value_box(
                  title = paste0(tb, " Momentum"),
                  value = round(feat_matrix$team_b_momentum_win_rate, 2),
                  showcase = icon("bolt"),
                  theme = ifelse(is_final && winner==tb, "warning", "danger")
                )
              )
            )
          )
        )
    )
    
    if(!is_final) {
        ui_out <- tagAppendChild(ui_out, 
          fluidRow(
            column(12,
              card(
                card_header(h4("MODEL PERFORMANCE (V4 Stacked Ensemble)", style="margin: 0;")),
                card_body(
                  p("Accuracy: 75.20% | Balanced Accuracy: 74.77% | ROC-AUC: 83.47%"),
                  p("F1: 0.778 | Brier Score: 0.1644 | Log Loss: 0.4968"),
                  hr(),
                  p(em("DISCLAIMER: This is a statistical machine-learning estimate based on historical pre-match information. It is not a guarantee of the actual match result."), style="color: gray; font-size: 0.8em;")
                )
              )
            )
          )
        )
    }
    return(ui_out)
}

# Define UI
ui <- page_navbar(
  theme = bs_theme(version = 5, bootswatch = "lumen", primary = "#2563EB", secondary = "#64748B", success = "#10B981", danger = "#EF4444", warning = "#D97706"),
  title = "HOCKEY WORLD CUP 2026",
  
  nav_panel("Match Predictor", icon = icon("magnifying-glass-chart"),
    layout_sidebar(
      sidebar = sidebar(
        selectInput("team_a", "Team A:", choices = teams, selected = "India"),
        selectInput("team_b", "Team B:", choices = teams, selected = "Australia"),
        dateInput("match_date", "Match Date:", value = "2026-08-15"),
        selectInput("tournament", "Tournament:", choices = c("WORLD_CUP", "OLYMPICS", "PRO_LEAGUE", "TEST_MATCH", "OTHER"), selected = "WORLD_CUP"),
        actionButton("predict_btn", "PREDICT", class = "btn-primary btn-lg", style = "width: 100%; margin-top: 20px;")
      ),
      uiOutput("prediction_ui")
    )
  ),
  
  nav_panel("World Cup Final", icon = icon("trophy"),
    div(style = "max-width: 900px; margin: 0 auto; padding-top: 20px;",
        uiOutput("world_cup_final_ui")
    )
  )
)

# Define Server Logic
server <- function(input, output) {
  
  # Standard Predictor
  observeEvent(input$predict_btn, {
    req(input$team_a, input$team_b, input$match_date)
    output$prediction_ui <- renderUI({
      generate_prediction_ui(input$team_a, input$team_b, as.Date(input$match_date), is_final = FALSE)
    })
  })
  
  # World Cup Final Automatic Predictor
  output$world_cup_final_ui <- renderUI({
      # Calculate top 2 teams globally
      latest_elo <- df %>% arrange(desc(match_date)) %>% group_by(team_a) %>% slice(1) %>% ungroup() %>% select(team = team_a, elo = team_a_elo_k20, date = match_date)
      latest_elo_b <- df %>% arrange(desc(match_date)) %>% group_by(team_b) %>% slice(1) %>% ungroup() %>% select(team = team_b, elo = team_b_elo_k20, date = match_date)
      all_elo <- bind_rows(latest_elo, latest_elo_b) %>% group_by(team) %>% arrange(desc(date)) %>% slice(1) %>% ungroup() %>% arrange(desc(elo))
      
      # Exclude teams that have been eliminated from the 2026 World Cup
      eliminated_teams <- c("Belgium")
      active_elo <- all_elo %>% filter(!(team %in% eliminated_teams))
      
      top_2 <- head(active_elo, 2)$team
      m_date <- as.Date("2026-08-30")
      
      generate_prediction_ui(top_2[1], top_2[2], m_date, is_final = TRUE)
  })
}

# Run the application 
shinyApp(ui = ui, server = server)
