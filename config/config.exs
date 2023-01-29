import Config

config :ffc_ex,
  prefix: "ffc:"

config :nostrum,
  token: System.get_env("BOT_TOKEN") || File.read!("token.txt"),
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
