%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: [
        # Pre-existing issues — disable until refactored
        {Credo.Check.Refactor.FunctionArity, false},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Readability.MaxLineLength, false},
        {Credo.Check.Refactor.Nesting, false},
        {Credo.Check.Refactor.WithClauses, false},
        {Credo.Check.Readability.SinglePipe, false},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.PreferImplicitTry, false},
        {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, false},
        {Credo.Check.Refactor.RedundantWithClauseResult, false}
      ]
    }
  ]
}
