use Mix.Config

config :riemannx,
  host: "localhost",
  tcp: [port: 5555, pool_size: 0],
  udp: [port: 5555, pool_size: 0]
