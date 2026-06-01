import Config

# ------------------------------------------------------------------
# Runtime configuration (evaluated at release boot, not at build time)
# ------------------------------------------------------------------

if config_env() == :prod do
  # Database path — resolved at boot from DATABASE_PATH env var.
  config :symphony_elixir, SymphonyElixir.Repo,
    database: System.get_env("DATABASE_PATH") || Path.expand("../symphony_prod.db", __DIR__)
end
