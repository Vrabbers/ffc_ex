import Config

config :logger,
  level: if(Mix.env() == :prod, do: :info, else: :debug)

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

config :hammer,
  backend:
    {Hammer.Backend.ETS, [expiry_ms: :timer.minutes(10), cleanup_interval_ms: :timer.minutes(2)]}
