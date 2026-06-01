ExUnit.start(exclude: [:skip])
Code.require_file("support/snapshot_support.exs", __DIR__)
Code.require_file("support/test_support.exs", __DIR__)

# Run pending migrations before entering sandbox mode
Ecto.Migrator.run(SymphonyElixir.Repo, :up, all: true)

Ecto.Adapters.SQL.Sandbox.mode(SymphonyElixir.Repo, :manual)
