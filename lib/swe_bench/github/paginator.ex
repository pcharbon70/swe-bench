defmodule SweBench.GitHub.Paginator do
  @moduledoc """
  Pagination handling for GitHub API responses.

  Automatically handles GitHub's 100-item page limits and provides
  streaming pagination for large datasets without memory issues.
  """

  require Logger

  alias SweBench.GitHub.Client

  @doc """
  Fetches all pages of a paginated GitHub API endpoint.
  Returns a stream of items for memory-efficient processing.
  """
  def stream_all_pages(client, path, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 100)
    initial_query = Keyword.get(opts, :query, [])

    Stream.resource(
      fn -> {1, true, initial_query} end,
      fn
        {_page, false, _query} ->
          {:halt, nil}

        {page, true, query} ->
          query_with_page = Keyword.merge(query, page: page, per_page: per_page)

          case Client.api_get(client, path, query: query_with_page) do
            {:ok, items} when is_list(items) ->
              has_more = length(items) == per_page
              {items, {page + 1, has_more, query}}

            {:ok, response} when is_map(response) ->
              # Handle responses with data nested in 'items' or similar
              items = extract_items_from_response(response)
              has_more = length(items) == per_page
              {items, {page + 1, has_more, query}}

            {:error, reason} ->
              Logger.error("Pagination error on page #{page}: #{inspect(reason)}")
              {:halt, nil}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Fetches all pages and collects results into a list.
  Use with caution for large datasets - prefer stream_all_pages/3.
  """
  def fetch_all_pages(client, path, opts \\ []) do
    case stream_all_pages(client, path, opts) |> Enum.to_list() do
      items when is_list(items) ->
        {:ok, List.flatten(items)}

      error ->
        {:error, error}
    end
  end

  @doc """
  Fetches a specific page of results.
  """
  def fetch_page(client, path, page, opts \\ []) do
    per_page = Keyword.get(opts, :per_page, 100)
    query = Keyword.get(opts, :query, [])

    query_with_page = Keyword.merge(query, page: page, per_page: per_page)

    case Client.api_get(client, path, query: query_with_page) do
      {:ok, items} ->
        {:ok,
         %{
           items: items,
           page: page,
           per_page: per_page,
           has_more: is_list(items) && length(items) == per_page
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Estimates total pages based on GitHub's Link header.
  """
  def parse_link_header(headers) do
    case get_header_value(headers, "link") do
      nil ->
        %{last_page: nil, next_page: nil}

      link_header ->
        parse_link_relations(link_header)
    end
  end

  # Private helper functions

  defp extract_items_from_response(response) do
    cond do
      Map.has_key?(response, "items") -> response["items"]
      Map.has_key?(response, "data") -> response["data"]
      is_list(response) -> response
      true -> [response]
    end
  end

  defp get_header_value(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp parse_link_relations(link_header) do
    link_header
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn link, acc ->
      case parse_single_link(link) do
        {url, rel} -> Map.put(acc, rel, extract_page_from_url(url))
        nil -> acc
      end
    end)
  end

  defp parse_single_link(link) do
    case Regex.run(~r/<([^>]+)>;\s*rel="([^"]+)"/, link) do
      [_, url, rel] -> {url, String.to_atom(rel)}
      _ -> nil
    end
  end

  defp extract_page_from_url(url) do
    case URI.parse(url) do
      %URI{query: query} when is_binary(query) ->
        query
        |> URI.decode_query()
        |> Map.get("page", "1")
        |> String.to_integer()

      _ ->
        1
    end
  end
end
