# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.Error do
  @moduledoc """
  Structured PaveDB client error.

  `code` and `message` carry PaveDB's `code` and `error` envelope fields;
  `details` carries the optional structured context PaveDB sends alongside
  them. `status` is nil for failures raised before a response arrived.
  """

  defexception [:code, :message, :status, :details, :body]

  @type t :: %__MODULE__{
          code: String.t(),
          message: String.t(),
          status: non_neg_integer() | nil,
          details: map() | nil,
          body: term()
        }
end
