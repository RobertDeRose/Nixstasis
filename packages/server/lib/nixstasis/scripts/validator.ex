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
         :ok <- validate_body(body) do
      {:ok, %{front_matter: parsed_front_matter, body: body, rendered_content: render_stary(parsed_front_matter, body)}}
    end
  end

  def validate_content(_), do: {:error, "stary content must be a string"}

  def validate_front_matter(front_matter) when is_map(front_matter) do
    with :ok <- require_keys(front_matter),
         :ok <- require_name(front_matter),
         :ok <- require_schema(front_matter),
         :ok <- validate_schema_shape(front_matter["schema"] || front_matter[:schema]),
         :ok <- validate_version(front_matter["version"] || front_matter[:version]) do
      :ok
    end
  end

  def validate_front_matter(_), do: {:error, "front matter must be a map"}

  def validate_draft_status(status), do: validate_status(status, @allowed_statuses.draft, "invalid draft status")

  def validate_version_status(status),
    do: validate_status(status, @allowed_statuses.version, "invalid version status")

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

  defp normalize_front_matter(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp render_value(value) when is_binary(value) do
    if String.contains?(value, [": ", "\n", "#", "\""]) do
      "\"#{String.replace(value, "\"", "\\\"")}\""
    else
      value
    end
  end

  defp render_value(value) when is_map(value), do: Jason.encode!(value)
  defp render_value(value) when is_list(value), do: Jason.encode!(value)
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

  defp validate_status(status, allowed, error_message) when is_binary(status) do
    status
    |> from_status_string()
    |> validate_status(allowed, error_message)
  end

  defp validate_status(status, allowed, _error_message) when is_atom(status) do
    if status in allowed do
      :ok
    else
      {:error, "invalid status"}
    end
  end

  defp validate_status(_status, _allowed, error_message), do: {:error, error_message}

  defp has_key?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, String.to_atom(key))
  end
end
