defmodule Nixstasis.Provisioning.HTTPClient do
  @moduledoc false

  @default_timeout 30_000

  def submit(url, bytes, filename, opts \\ []) do
    response =
      Req.post(url,
        body: bytes,
        headers: [
          {"content-type", "application/octet-stream"},
          {"x-config-filename", filename}
        ],
        receive_timeout: Keyword.get(opts, :request_timeout_ms, @default_timeout),
        retry: false,
        redirect: false
      )

    case response do
      {:ok, %{status: 202, body: body}} -> parse_submission(body)
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, error_message(body)}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  def get_job(url, opts \\ []) do
    response =
      Req.get(url,
        receive_timeout: Keyword.get(opts, :request_timeout_ms, @default_timeout),
        retry: false,
        redirect: false
      )

    case response do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> decode_json(body)
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, error_message(body)}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp parse_submission(body) when is_map(body), do: {:ok, body}
  defp parse_submission(body), do: decode_json(body)

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, _value} -> {:error, :invalid_json}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp decode_json(_body), do: {:error, :invalid_json}

  defp error_message(%{"error" => message}) when is_binary(message), do: message
  defp error_message(%{error: message}) when is_binary(message), do: message
  defp error_message(body) when is_binary(body), do: String.slice(body, 0, 512)
  defp error_message(body), do: inspect(body)
end
