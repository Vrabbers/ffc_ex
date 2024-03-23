# FfcEx

Final fantastic card built with Elixir.

## Instructions

To set bot token, set the ``BOT_TOKEN`` environment variable *or* have a ``token.txt`` file locally.

**Please note that the bot *requires* the privileged ``message_content`` gateway intent**

To run the bot in an interactive environment, use ``iex -S mix`` (*or ``iex.bat -S mix`` for PowerShell*). To run
without IEx, use ``mix --no-halt``.

## Bot usage

To start a game type <kbd>/create</kbd> in a guild channel. Other users can then join in by pressing the join button. Once you've got all your friends in, press `Close and start` to start the game!
