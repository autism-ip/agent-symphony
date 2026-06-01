import Config

config :symphony_elixir, SymphonyElixir.Repo,
  database: Path.expand("../symphony_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5
