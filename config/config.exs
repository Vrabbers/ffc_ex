import Config

config :logger,
  level: :info

config :ffc_ex,
  prefix: if(Mix.env() == :prod, do: "ffc:", else: "ffd:"),
  color: if(Mix.env() == :prod, do: 0xFF3F3F, else: 0x4251F5)

config :nostrum,
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
