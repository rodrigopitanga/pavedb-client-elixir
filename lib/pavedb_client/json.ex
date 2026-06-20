# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.JSON do
  @moduledoc false

  @spec decode(binary()) :: {:ok, term()} | {:error, String.t()}
  def decode(binary) when is_binary(binary) do
    case :json.decode(binary) do
      value -> {:ok, value}
    end
  rescue
    _ -> {:error, "invalid JSON"}
  end

  @spec encode!(term()) :: binary()
  def encode!(value) do
    value
    |> :json.encode()
    |> IO.iodata_to_binary()
  end
end
