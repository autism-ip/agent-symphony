# agent-symphony - autonomous implementation orchestration
Elixir reference runtime + GitHub Actions gate + repository specification.

<directory>
.github/ - GitHub collaboration surface (workflows, PR template, media).
docs/ - planning records and long-form design notes.
elixir/ - Symphony Elixir worker runtime, tests, config, and Mix project.
</directory>

<config>
README.md - project positioning and entry path to the Elixir implementation.
SPEC.md - implementation contract and behavioral source of truth.
LICENSE - Apache 2.0 license terms.
NOTICE - attribution notice.
CLAUDE.md - L1 project map for agent navigation.
</config>

<architecture>
The root owns product intent and repository workflow; implementation detail lives under elixir/.
GitHub Actions call the Elixir Makefile as the single quality command surface.
</architecture>

[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
