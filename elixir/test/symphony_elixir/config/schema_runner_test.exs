defmodule SymphonyElixir.Config.SchemaRunnerTest do
  @moduledoc """
  [INPUT]: 依赖 SymphonyElixir.Config.Schema 的 parse/1 函数
  [OUTPUT]: 对外提供 runner 配置 schema 的测试覆盖
  [POS]: config 测试的 runner 配置验证，覆盖旧配置迁移与新配置解析
  [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
  """

  use ExUnit.Case, async: true

  alias SymphonyElixir.Config.Schema

  # ===========================================================================
  # Section 1: Current behavior — codex config parsing (must pass now)
  # ===========================================================================

  describe "Config.Schema.parse/1 with codex config (current behavior)" do
    test "parses config with codex command" do
      config = %{"codex" => %{"command" => "codex app-server"}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.command == "codex app-server"
    end

    test "parses codex config with custom timeout values" do
      config = %{
        "codex" => %{
          "command" => "codex app-server",
          "turn_timeout_ms" => 1_800_000,
          "read_timeout_ms" => 10_000,
          "stall_timeout_ms" => 600_000
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.turn_timeout_ms == 1_800_000
      assert settings.codex.read_timeout_ms == 10_000
      assert settings.codex.stall_timeout_ms == 600_000
    end

    test "codex command defaults to 'codex app-server'" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.command == "codex app-server"
    end

    test "codex turn_timeout_ms defaults to 3_600_000" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.turn_timeout_ms == 3_600_000
    end

    test "codex read_timeout_ms defaults to 5_000" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.read_timeout_ms == 5_000
    end

    test "codex stall_timeout_ms defaults to 300_000" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.stall_timeout_ms == 300_000
    end

    test "codex thread_sandbox defaults to 'workspace-write'" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.thread_sandbox == "workspace-write"
    end

    test "rejects negative turn_timeout_ms" do
      config = %{
        "codex" => %{
          "command" => "codex app-server",
          "turn_timeout_ms" => -1
        }
      }

      assert {:error, {:invalid_workflow_config, _reason}} = Schema.parse(config)
    end

    test "rejects negative read_timeout_ms" do
      config = %{
        "codex" => %{
          "command" => "codex app-server",
          "read_timeout_ms" => -1
        }
      }

      assert {:error, {:invalid_workflow_config, _reason}} = Schema.parse(config)
    end

    test "rejects negative stall_timeout_ms" do
      config = %{
        "codex" => %{
          "command" => "codex app-server",
          "stall_timeout_ms" => -1
        }
      }

      assert {:error, {:invalid_workflow_config, _reason}} = Schema.parse(config)
    end

    test "accepts zero stall_timeout_ms" do
      config = %{
        "codex" => %{
          "command" => "codex app-server",
          "stall_timeout_ms" => 0
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.codex.stall_timeout_ms == 0
    end
  end

  # ===========================================================================
  # Section 2: Runner config tests — NEW functionality (tagged :pending)
  # These will fail until the runner schema is implemented in schema.ex
  # ===========================================================================

  describe "Config.Schema.parse/1 runner migration (backward compat)" do
    @tag :pending
    test "旧配置自动迁移: top-level codex migrates to runner.type = 'codex'" do
      config = %{"codex" => %{"command" => "codex app-server"}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "codex"
      assert settings.runner.codex.command == "codex app-server"
    end

    @tag :pending
    test "旧配置自动迁移: codex defaults preserved after migration" do
      config = %{"codex" => %{}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "codex"
      assert settings.runner.codex.command == "codex app-server"
      assert settings.runner.codex.turn_timeout_ms == 3_600_000
      assert settings.runner.codex.stall_timeout_ms == 300_000
    end

    @tag :pending
    test "旧配置自动迁移: codex timeout values preserved after migration" do
      config = %{
        "codex" => %{
          "command" => "custom-codex",
          "turn_timeout_ms" => 1_800_000,
          "stall_timeout_ms" => 600_000
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "codex"
      assert settings.runner.codex.command == "custom-codex"
      assert settings.runner.codex.turn_timeout_ms == 1_800_000
      assert settings.runner.codex.stall_timeout_ms == 600_000
    end
  end

  describe "Config.Schema.parse/1 runner config (new format)" do
    @tag :pending
    test "新配置正常解析: runner with type 'claude'" do
      config = %{
        "runner" => %{
          "type" => "claude",
          "claude" => %{"command" => "claude"}
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "claude"
      assert settings.runner.claude.command == "claude"
    end

    @tag :pending
    test "新配置正常解析: runner with type 'codex'" do
      config = %{
        "runner" => %{
          "type" => "codex",
          "codex" => %{"command" => "codex app-server"}
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "codex"
      assert settings.runner.codex.command == "codex app-server"
    end

    @tag :pending
    test "新配置正常解析: runner config takes precedence over legacy codex" do
      config = %{
        "codex" => %{"command" => "old-codex"},
        "runner" => %{
          "type" => "codex",
          "codex" => %{"command" => "new-codex"}
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.type == "codex"
      assert settings.runner.codex.command == "new-codex"
    end
  end

  describe "Config.Schema.parse/1 runner type validation" do
    @tag :pending
    test "验证: runner.type must be 'codex' or 'claude'" do
      config = %{"runner" => %{"type" => "invalid_type"}}

      assert {:error, {:invalid_workflow_config, reason}} = Schema.parse(config)
      assert reason =~ "runner.type"
    end

    @tag :pending
    test "验证: runner.type is required when runner key present" do
      config = %{"runner" => %{"claude" => %{"command" => "claude"}}}

      assert {:error, {:invalid_workflow_config, reason}} = Schema.parse(config)
      assert reason =~ "runner.type"
    end

    @tag :pending
    test "验证: runner.type rejects empty string" do
      config = %{"runner" => %{"type" => ""}}

      assert {:error, {:invalid_workflow_config, reason}} = Schema.parse(config)
      assert reason =~ "runner.type"
    end
  end

  describe "Config.Schema.parse/1 ClaudeConfig defaults" do
    @tag :pending
    test "ClaudeConfig: command defaults to 'claude'" do
      config = %{"runner" => %{"type" => "claude", "claude" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.claude.command == "claude"
    end

    @tag :pending
    test "ClaudeConfig: turn_timeout_ms defaults to 300_000" do
      config = %{"runner" => %{"type" => "claude", "claude" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.claude.turn_timeout_ms == 300_000
    end

    @tag :pending
    test "ClaudeConfig: stall_timeout_ms defaults to 0 (disabled)" do
      config = %{"runner" => %{"type" => "claude", "claude" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.claude.stall_timeout_ms == 0
    end

    @tag :pending
    test "ClaudeConfig: max_turns defaults to 10" do
      config = %{"runner" => %{"type" => "claude", "claude" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.claude.max_turns == 10
    end

    @tag :pending
    test "ClaudeConfig: custom values override all defaults" do
      config = %{
        "runner" => %{
          "type" => "claude",
          "claude" => %{
            "command" => "custom-claude",
            "turn_timeout_ms" => 600_000,
            "stall_timeout_ms" => 120_000,
            "max_turns" => 20
          }
        }
      }

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.claude.command == "custom-claude"
      assert settings.runner.claude.turn_timeout_ms == 600_000
      assert settings.runner.claude.stall_timeout_ms == 120_000
      assert settings.runner.claude.max_turns == 20
    end
  end

  describe "Config.Schema.parse/1 CodexConfig in runner" do
    @tag :pending
    test "CodexConfig: default command is 'codex app-server'" do
      config = %{"runner" => %{"type" => "codex", "codex" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.codex.command == "codex app-server"
    end

    @tag :pending
    test "CodexConfig: default turn_timeout_ms is 3_600_000" do
      config = %{"runner" => %{"type" => "codex", "codex" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.codex.turn_timeout_ms == 3_600_000
    end

    @tag :pending
    test "CodexConfig: default stall_timeout_ms is 300_000" do
      config = %{"runner" => %{"type" => "codex", "codex" => %{}}}

      assert {:ok, %Schema{} = settings} = Schema.parse(config)
      assert settings.runner.codex.stall_timeout_ms == 300_000
    end
  end
end
