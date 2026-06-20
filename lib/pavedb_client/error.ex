# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.Error do
  @moduledoc """
  Structured PaveDB client error.
  """

  defexception [:code, :message, :status, :type, :body]

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          status: non_neg_integer() | nil,
          type: String.t() | nil,
          body: term()
        }
end
