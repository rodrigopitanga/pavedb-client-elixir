# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClientExamplesTest do
  use ExUnit.Case, async: true

  for {directory, command} <- [
        {"1-concurrent-evaluation", "mix run examples/1-concurrent-evaluation/run.exs"},
        {"2-query-replay-drift", "mix run examples/2-query-replay-drift/run.exs"}
      ] do
    test "#{directory} has its documented command" do
      directory = unquote(directory)
      command = unquote(command)
      root = Path.expand("../examples/#{directory}", __DIR__)

      assert File.regular?(Path.join(root, "run.exs"))
      assert File.read!(Path.join(root, "README.md")) =~ command
    end
  end
end
