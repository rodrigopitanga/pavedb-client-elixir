# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBExamples.QueryReplayDrift do
  def run do
    collection = seeded_collection("book-query-replay")
    result!(PaveDBClient.Collection.search(collection, "query replay", k: 10))

    collection
    |> PaveDBClient.Collection.list_queries(limit: 100)
    |> result!()
    |> Map.fetch!("queries")
    |> Task.async_stream(&check(collection, &1["query_id"]),
      max_concurrency: 8,
      timeout: 60_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.map(&task_result/1)
    |> then(fn rows ->
      %{checked: length(rows), drifted: Enum.filter(rows, & &1.drifted), rows: rows}
    end)
  end

  defp seeded_collection(name) do
    client = PaveDBClient.connect(tenant: System.get_env("PAVEDB_TENANT", "book"))
    collection = result!(PaveDBClient.create_collection(client, name))

    [
      {"PaveDB keeps a query log for replay and inspection.", "query-log"},
      {"Replay compares stored result ids with current search results.", "replay"}
    ]
    |> Enum.each(fn {text, docid} ->
      result!(PaveDBClient.Collection.add(collection, text, docid: docid))
    end)

    collection
  end

  defp check(collection, query_id) do
    original = result!(PaveDBClient.Collection.get_query(collection, query_id))
    replay = result!(PaveDBClient.Collection.replay_query(collection, query_id))
    original_ids = get_in(original, ["query", "result_ids"])
    replayed_ids = Enum.map(replay["matches"], & &1["id"])

    %{query_id: query_id, drifted: original_ids != replayed_ids,
      original_ids: original_ids, replayed_ids: replayed_ids}
  end

  defp task_result({:ok, result}), do: result
  defp task_result({:exit, reason}) do
    %{query_id: nil, drifted: true, error: inspect(reason)}
  end

  defp result!({:ok, value}), do: value
  defp result!({:error, error}), do: raise(PaveDBClient.format_error(error))
end

PaveDBExamples.QueryReplayDrift.run() |> IO.inspect(label: "query replay drift")
