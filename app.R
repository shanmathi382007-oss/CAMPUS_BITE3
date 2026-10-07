library(shiny)

ui <- fluidPage(
  tags$head(
    tags$style(HTML("\
      body {
        min-height: 100vh;
        background: linear-gradient(135deg, #d9f4ef, #fff1cf);
        color: #183d3a;
      }
      .game-wrap {
        max-width: 520px;
        margin: 55px auto;
        padding: 0 18px;
      }
      .game-panel {
        padding: 32px;
        background: #ffffff;
        border: 2px solid #b8e3d8;
        border-radius: 8px;
        box-shadow: 0 12px 32px rgba(24, 61, 58, 0.12);
      }
      .game-title {
        margin: 0 0 10px;
        color: #176b61;
        font-size: 30px;
        font-weight: 800;
        text-align: center;
      }
      .game-subtitle {
        margin-bottom: 26px;
        color: #58716d;
        text-align: center;
      }
      .btn {
        border: 0;
        border-radius: 6px;
        font-weight: 700;
      }
      .btn-primary {
        background: #168477;
      }
      .btn-primary:hover {
        background: #10695f;
      }
      .btn-default {
        background: #ffcf68;
        color: #463611;
      }
      .feedback {
        min-height: 58px;
        margin: 22px 0 16px;
        padding: 16px;
        border-radius: 6px;
        font-size: 20px;
        font-weight: 700;
        text-align: center;
      }
      .feedback-neutral {
        background: #edf5f3;
        color: #42635e;
      }
      .feedback-hint {
        background: #fff1cf;
        color: #805400;
      }
      .feedback-win {
        background: #dff5dd;
        color: #28652a;
      }
      .attempts {
        color: #365c57;
        font-size: 17px;
        font-weight: 700;
        text-align: center;
      }
      @media (max-width: 480px) {
        .game-wrap { margin-top: 24px; }
        .game-panel { padding: 24px 20px; }
        .game-title { font-size: 25px; }
      }
    "))
  ),
  div(
    class = "game-wrap",
    div(
      class = "game-panel",
      h1(class = "game-title", "🎯 Number Guessing Game"),
      p(class = "game-subtitle", "Pick a number from 1 to 100."),
      numericInput(
        "guess",
        "Your guess",
        value = 1,
        min = 1,
        max = 100,
        step = 1
      ),
      div(
        style = "display: flex; gap: 10px;",
        actionButton("guess_button", "Guess", class = "btn-primary"),
        actionButton("new_game", "New Game", class = "btn-default")
      ),
      uiOutput("feedback"),
      div(class = "attempts", textOutput("attempts"))
    )
  )
)

server <- function(input, output, session) {
  secret_number <- reactiveVal(sample(1:100, 1))
  attempts <- reactiveVal(0)
  won <- reactiveVal(FALSE)
  message <- reactiveVal(list(text = "Make your first guess!", style = "neutral"))

  observeEvent(input$guess_button, {
    if (won()) {
      return()
    }

    guess <- input$guess
    if (is.null(guess) || is.na(guess) || guess < 1 || guess > 100 || guess != as.integer(guess)) {
      message(list(text = "Enter a whole number from 1 to 100.", style = "neutral"))
      return()
    }

    attempts(attempts() + 1)

    if (guess > secret_number()) {
      message(list(text = "Too High!", style = "hint"))
    } else if (guess < secret_number()) {
      message(list(text = "Too Low!", style = "hint"))
    } else {
      message(list(text = "🎉 Correct! You Won!", style = "win"))
      won(TRUE)
    }
  })

  observeEvent(input$new_game, {
    secret_number(sample(1:100, 1))
    attempts(0)
    won(FALSE)
    message(list(text = "New number ready. Make a guess!", style = "neutral"))
  })

  output$feedback <- renderUI({
    current_message <- message()
    div(
      class = paste("feedback", paste0("feedback-", current_message$style)),
      current_message$text
    )
  })

  output$attempts <- renderText({
    paste("Attempts:", attempts())
  })
}

shinyApp(ui = ui, server = server)