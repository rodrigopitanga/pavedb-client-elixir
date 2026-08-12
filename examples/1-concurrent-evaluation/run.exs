# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBExamples.ConcurrentEvaluation do
  @max_attempts 4
  @base_delay_ms 200

  def run do
    collection = seeded_collection("book-evaluation")

    [
      %{query: "teach selection and iteration", expected_codes: ["KS3-CS-01"]},
      %{query: "represent numbers in binary", expected_codes: ["KS3-CS-04"]}
    ]
    |> Task.async_stream(&evaluate(collection, &1),
      max_concurrency: 16,
      timeout: 60_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{ok: 0, recall_sum: 0.0, failed: []}, &fold/2)
    |> finalize()
  end

  defp seeded_collection(name) do
    client = PaveDBClient.connect(tenant: System.get_env("PAVEDB_TENANT", "book"))
    collection = result!(PaveDBClient.create_collection(client, name))

    [
      {"Teach selection and iteration with simple programs.", "KS3-CS-01"},
      {"Represent positive integers in binary notation.", "KS3-CS-04"}
    ]
    |> Enum.each(fn {text, code} ->
      result!(
        PaveDBClient.Collection.add(collection, text,
          docid: code,
          metadata: %{"code" => code}
        )
      )
    end)

    collection
  end

  defp evaluate(collection, %{query: query, expected_codes: expected_codes}) do
    case retry_search(collection, query) do
      {:ok, %{"matches" => matches}} ->
        codes =
          for match <- matches,
              code = get_in(match, ["meta", "code"]),
              code,
              do: code

        {:ok, %{query: query, recall: recall(codes, expected_codes)}}

      {:error, error} ->
        {:error, %{query: query, code: error.code, status: error.status}}
    end
  end

  defp retry_search(collection, query, attempt \\ 1) do
    case PaveDBClient.Collection.search(collection, query, k: 10) do
      {:error, error} = failed ->
        if retryable?(error) and attempt < @max_attempts do
          delay = @base_delay_ms * round(:math.pow(2, attempt - 1))
          Process.sleep(:rand.uniform(delay))
          retry_search(collection, query, attempt + 1)
        else
          failed
        end

      result ->
        result
    end
  end

  defp retryable?(%PaveDBClient.Error{status: 429}), do: true

  defp retryable?(%PaveDBClient.Error{status: 503, code: code})
       when code in ["search_overloaded", "search_timeout", "embedder_unavailable"],
       do: true

  defp retryable?(_), do: false

  defp recall(codes, expected_codes) do
    hits = Enum.count(expected_codes, &(&1 in codes))
    if expected_codes == [], do: 1.0, else: hits / length(expected_codes)
  end

  defp fold({:ok, {:ok, result}}, acc),
    do: %{acc | ok: acc.ok + 1, recall_sum: acc.recall_sum + result.recall}

  defp fold({:ok, {:error, error}}, acc), do: %{acc | failed: [error | acc.failed]}
  defp fold({:exit, reason}, acc), do: %{acc | failed: [%{reason: reason} | acc.failed]}

  defp finalize(%{ok: ok, recall_sum: sum, failed: failed}) do
    %{
      queries_ok: ok,
      mean_recall: if(ok == 0, do: 0.0, else: Float.round(sum / ok, 3)),
      failed: Enum.reverse(failed)
    }
  end

  defp result!({:ok, value}), do: value
  defp result!({:error, error}), do: raise(PaveDBClient.format_error(error))
end

PaveDBExamples.ConcurrentEvaluation.run() |> IO.inspect(label: "concurrent evaluation")
