use Mix.Config

config :riemannx, [
  host: "127.0.0.1",
  tcp: [port: 5555, pool_size: 1],
  udp: [port: 5555, pool_size: 1],
  tls: [port: 5554, pool_size: 1],
  tcp_port: 5555,
  udp_port: 5555,
  pool_size: 1
]
