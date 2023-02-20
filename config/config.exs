import Config

config :logger,
  level: :info

config :ffc_ex,
  prefix: if(Mix.env() == :prod, do: "ffc:", else: "ffd:"),
  color: if(Mix.env() == :prod, do: 0x4251F5, else: 0xFFFFFF)

config :nostrum,
  gateway_intents: [
    :guild_messages,
    :direct_messages,
    :message_content
  ]
