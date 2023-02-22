import Config

config :logger,
  level: :debug

config :ffc_ex,
  prefix: if(Mix.env() == :prod, do: "ffc:", else: "ffd:"),
  color: if(Mix.env() == :prod, do: 0xFF3F3F, else: 0x4251F5),
  debug_guild: System.get_env("DEBUG_GUILD")

config :nostrum,
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
