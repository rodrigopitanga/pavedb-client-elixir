# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClientTest do
  use ExUnit.Case, async: true

  test "exposes a version" do
    assert PaveDBClient.version() == "0.1.0"
  end
end
