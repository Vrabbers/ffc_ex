import Config

config :logger,
  level: :info

config :ffc_ex,
  prefix: "ffc:",
  color: 0x4251F5

config :nostrum,
  token: System.get_env("BOT_TOKEN") || File.read!("token.txt") |> String.trim(),
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
