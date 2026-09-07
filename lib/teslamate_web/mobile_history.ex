defmodule TeslaMateWeb.MobileHistory do
  @moduledoc false
  import Ecto.Query
  alias TeslaMate.Repo

  def options(params) do
    with {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, from} <- parse_date(params["from"]),
         {:ok, to} <- parse_date(params["to"]),
         true <- is_nil(from) or is_nil(to) or DateTime.compare(from, to) == :lt,
         {:ok, cursor} <- parse_cursor(params["cursor"]) do
      {:ok, %{limit: limit, from: from, to: to, cursor: cursor}}
    else
      _ -> {:error, "invalid_history_parameters"}
    end
  end

  def page(query, options, serialize) do
    rows =
      query
      |> date_from(options.from)
      |> date_to(options.to)
      |> before_cursor(options.cursor)
      |> order_by([r], desc: r.start_date, desc: r.id)
      |> limit(^(options.limit + 1))
      |> Repo.all()

    records = Enum.take(rows, options.limit)
    cursor = if length(rows) > options.limit, do: encode_cursor(List.last(records))
    %{data: Enum.map(records, serialize), pagination: %{next_cursor: cursor}}
  end

  # Bound the response in SQL, preserving the first and last point. Database work
  # still scales with the record's samples; this is not a substitute for profiling.
  def samples(query, schema, fields) do
    ranked =
      from r in query,
        select: %{
          id: r.id,
          index: over(row_number(), order_by: [asc: r.date, asc: r.id]),
          total: over(count(r.id))
        }

    rows =
      from(s in subquery(ranked),
        join: r in ^schema,
        on: r.id == s.id,
        where:
          fragment(
            "mod(? - 1, GREATEST(1, CEIL((? - 1)::numeric / 1999)::bigint)) = 0 OR ? = ?",
            s.index,
            s.total,
            s.index,
            s.total
          ),
        order_by: s.index,
        select: %{values: map(r, ^fields), total: s.total}
      )
      |> Repo.all()

    total =
      case rows do
        [%{total: total} | _] -> total
        [] -> 0
      end

    {Enum.map(rows, & &1.values),
     %{total: total, returned: length(rows), downsampled: total > length(rows)}}
  end

  defp date_from(query, nil), do: query
  defp date_from(query, date), do: where(query, [r], r.start_date >= ^date)
  defp date_to(query, nil), do: query
  defp date_to(query, date), do: where(query, [r], r.start_date < ^date)
  defp before_cursor(query, nil), do: query

  defp before_cursor(query, {date, id}) do
    where(query, [r], r.start_date < ^date or (r.start_date == ^date and r.id < ^id))
  end

  defp parse_limit(nil), do: {:ok, 100}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit > 0 and limit <= 500 -> {:ok, limit}
      _ -> :error
    end
  end

  defp parse_limit(_), do: :error

  defp parse_date(nil), do: {:ok, nil}

  defp parse_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error

  defp parse_cursor(nil), do: {:ok, nil}

  defp parse_cursor(value) when is_binary(value) and byte_size(value) <= 512 do
    with {:ok, json} <- Base.url_decode64(value, padding: false),
         {:ok, [timestamp, id]} <- Jason.decode(json),
         true <- is_integer(id) and id > 0 and id <= 2_147_483_647,
         {:ok, %DateTime{} = date} <- parse_date(timestamp) do
      {:ok, {date, id}}
    else
      _ -> :error
    end
  end

  defp parse_cursor(_), do: :error

  defp encode_cursor(record) do
    [DateTime.to_iso8601(record.start_date), record.id]
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end
end
