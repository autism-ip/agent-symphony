import Config

# Production overrides.
# Database path is resolved from DATABASE_PATH env var, falling back to symphony_prod.db.
# Secrets are resolved at runtime via Config.Schema.resolve_secret_setting/2.

config :symphony_elixir, SymphonyElixir.Repo, database: System.get_env("DATABASE_PATH") || Path.expand("../symphony_prod.db", __DIR__)
