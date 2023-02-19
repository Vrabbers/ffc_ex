import Config

config :nostrum,
  token: (System.get_env("BOT_TOKEN") || File.read!("token.txt")) |> String.trim()
