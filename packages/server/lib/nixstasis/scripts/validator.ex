defmodule Nixstasis.Scripts.Validator do
  @moduledoc """
  Server-side validation and rendering helpers for Stary scripts.

  The server keeps the validation surface small: it checks front matter shape,
  canonical rendering, and structural constraints that can be verified without
  executing the client runtime.
  """

  @required_front_matter_keys ~w(name schema)
  @allowed_statuses %{
    draft: [:draft, :validated, :archived],
    version: [:candidate, :validated, :deployed, :superseded, :archived]
  }

  def render_stary(front_matter, body) when is_map(front_matter) and is_binary(body) do
    front =
      front_matter
      |> normalize_front_matter()
      |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{render_value(value)}" end)

    ["---", front, "---", String.trim_leading(body, "\n")] |> Enum.join("\n") |> String.trim_trailing()
  end

  def render_stary(_, _), do: {:error, "front matter and body must be provided"}

  def validate_content(content) when is_binary(content) do
    with {:ok, front_matter, body} <- split_front_matter(content),
         {:ok, parsed_front_matter} <- parse_front_matter(front_matter),
         :ok <- validate_front_matter(parsed_front_matter),
         :ok <- validate_body(body),
         :ok <- validate_starlark_body(body) do
      {:ok, %{front_matter: parsed_front_matter, body: body, rendered_content: render_stary(parsed_front_matter, body)}}
    end
  end

  def validate_content(_), do: {:error, "stary content must be a string"}

  def validate_front_matter(front_matter) when is_map(front_matter) do
    with :ok <- require_keys(front_matter),
         :ok <- require_name(front_matter),
         :ok <- require_schema(front_matter),
         :ok <- validate_schema_shape(front_matter["schema"] || front_matter[:schema]) do
      validate_version(front_matter["version"] || front_matter[:version])
    end
  end

  def validate_front_matter(_), do: {:error, "front matter must be a map"}

  def validate_draft_status(status) when is_atom(status) and status in @allowed_statuses.draft, do: :ok
  def validate_draft_status(status) when is_binary(status), do: validate_draft_status(from_status_string(status))

  def validate_draft_status(_), do: {:error, "invalid draft status"}

  def validate_version_status(status) when is_atom(status) and status in @allowed_statuses.version, do: :ok
  def validate_version_status(status) when is_binary(status), do: validate_version_status(from_status_string(status))

  def validate_version_status(_), do: {:error, "invalid version status"}

  defp split_front_matter(content) do
    trimmed = String.trim_leading(content, "\ufeff")

    if String.starts_with?(trimmed, "---\n") or String.starts_with?(trimmed, "---\r\n") do
      rest = String.replace_prefix(trimmed, "---\r\n", "")
      rest = String.replace_prefix(rest, "---\n", "")

      case String.split(rest, ~r/\r?\n---\r?\n/, parts: 2) do
        [front, body] -> {:ok, front, body}
        _ -> {:error, "front matter terminator not found"}
      end
    else
      {:error, "front matter must start with ---"}
    end
  end

  defp parse_front_matter(front_matter) do
    case YamlElixir.read_from_string(front_matter) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "front matter must decode to a map"}
      {:error, reason} -> {:error, "parse front matter: #{inspect(reason)}"}
    end
  end

  defp require_keys(front_matter) do
    missing =
      Enum.reject(@required_front_matter_keys, fn key ->
        has_key?(front_matter, key)
      end)

    case missing do
      [] -> :ok
      _ -> {:error, "front matter missing required keys: #{Enum.join(missing, ", ")}"}
    end
  end

  defp require_name(front_matter) do
    case front_matter["name"] || front_matter[:name] do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, "front matter name must be a non-empty string"}
        else
          :ok
        end

      _ ->
        {:error, "front matter name must be a non-empty string"}
    end
  end

  defp require_schema(front_matter) do
    case front_matter["schema"] || front_matter[:schema] do
      value when is_map(value) -> :ok
      _ -> {:error, "front matter schema must be a map"}
    end
  end

  defp validate_schema_shape(schema) when is_map(schema) do
    case schema["type"] || schema[:type] do
      nil -> :ok
      "object" -> :ok
      _ -> {:error, "schema type must be object when provided"}
    end
  end

  defp validate_schema_shape(_), do: {:error, "front matter schema must be a map"}

  defp validate_version(nil), do: :ok
  defp validate_version(version) when is_binary(version) and version != "", do: :ok
  defp validate_version(_), do: {:error, "front matter version must be a non-empty string when provided"}

  defp validate_body(body) when is_binary(body) do
    if String.trim(body) == "" do
      {:error, "script body must not be empty"}
    else
      :ok
    end
  end

  defp validate_body(_), do: {:error, "script body must be a string"}

  defp validate_starlark_body(body) do
    cond do
      Regex.match?(~r/^\s*def\s+[A-Za-z_]\w*\s*\([^\n]*\)\s*:/m, body) == false ->
        {:error, "Starlark parse error: expected function definition"}

      balanced?(body, ?(, ?)) == false or balanced?(body, ?[, ?]) == false or balanced?(body, ?{, ?}) == false ->
        {:error, "Starlark parse error: unbalanced delimiters"}

      true ->
        validate_starlark_statements(body)
    end
  end

  defp validate_starlark_statements(body) do
    body
    |> String.split(~r/\r?\n/)
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {line, line_number}, :ok ->
      case validate_starlark_line(line) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, "Starlark parse error on line #{line_number}: #{reason}"}}
      end
    end)
  end

  defp validate_starlark_line(line) do
    line = strip_comment(line) |> String.trim()

    cond do
      line == "" ->
        :ok

      String.ends_with?(line, ":") ->
        validate_starlark_block_header(String.trim_trailing(line, ":") |> String.trim())

      true ->
        :ok
    end
  end

  defp validate_starlark_block_header(""), do: {:error, "empty block header"}

  defp validate_starlark_block_header(header) do
    cond do
      Regex.match?(~r/^def\s+[A-Za-z_]\w*\s*\([^\n]*\)$/, header) -> :ok
      Regex.match?(~r/^if\s+\S.+$/, header) -> :ok
      Regex.match?(~r/^elif\s+\S.+$/, header) -> :ok
      header == "else" -> :ok
      Regex.match?(~r/^for\s+\S.+\s+in\s+\S.+$/, header) -> :ok
      true -> {:error, "invalid block header"}
    end
  end

  defp strip_comment(line) do
    line
    |> String.split("#", parts: 2)
    |> hd()
  end

  defp balanced?(body, open, close) do
    body
    |> String.to_charlist()
    |> Enum.reduce_while(0, fn
      ^open, count -> {:cont, count + 1}
      ^close, 0 -> {:halt, -1}
      ^close, count -> {:cont, count - 1}
      _, count -> {:cont, count}
    end) == 0
  end

  defp normalize_front_matter(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp render_value(value) when is_binary(value), do: inspect(value)
  defp render_value(value) when is_map(value), do: inspect(value)
  defp render_value(value) when is_list(value), do: inspect(value)
  defp render_value(value), do: to_string(value)

  defp from_status_string(status) do
    case String.trim(status) do
      "draft" -> :draft
      "validated" -> :validated
      "archived" -> :archived
      "candidate" -> :candidate
      "deployed" -> :deployed
      "superseded" -> :superseded
      _ -> nil
    end
  end

  defp has_key?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, String.to_atom(key))
  end
end
