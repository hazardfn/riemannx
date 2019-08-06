use Mix.Config

config :riemannx,
  host: "127.0.0.1",
  tcp: [port: 5555, pool_size: 1, options: [reuseaddr: true]],
  udp: [port: 5555, pool_size: 1],
  tls: [port: 5554, pool_size: 1, options: [reuseaddr: true]],
  queue_settings: [size: 10, interval: {100, :milliseconds}],
  checkout_timeout: 30_000,
  tcp_port: 5555,
  udp_port: 5555
