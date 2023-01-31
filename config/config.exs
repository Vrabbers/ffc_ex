import Config

config :ffc_ex,
  prefix: "ffc:",
  color: 0xff0000

config :nostrum,
  token: System.get_env("BOT_TOKEN") || File.read!("token.txt") |> String.trim(),
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
