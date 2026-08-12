# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.JSON do
  @moduledoc false

  @spec decode(binary()) :: {:ok, term()} | {:error, String.t()}
  def decode(binary) when is_binary(binary) do
    {:ok, :json.decode(binary)}
  rescue
    _ -> {:error, "invalid JSON"}
  end

  @spec encode(term()) :: {:ok, binary()} | {:error, String.t()}
  def encode(value) do
    {:ok, value |> :json.encode() |> IO.iodata_to_binary()}
  rescue
    # :json rejects tuples and structs, so a caller's metadata or filters can
    # fail here rather than at the server.
    _ -> {:error, "value cannot be encoded as JSON"}
  end
end
