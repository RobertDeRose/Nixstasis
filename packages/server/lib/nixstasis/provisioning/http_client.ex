defmodule Nixstasis.Provisioning.HTTPClient do
  @moduledoc false

  @default_timeout 30_000
  @max_response_bytes 1 * 1024 * 1024

  @doc false
  def max_response_size, do: @max_response_bytes

  def submit(url, bytes, filename, opts \\ []) do
    response =
      Req.post(
        url,
        [
          body: bytes,
          headers: [
            {"content-type", "application/octet-stream"},
            {"x-config-filename", filename}
          ],
          receive_timeout: Keyword.get(opts, :request_timeout_ms, @default_timeout),
          retry: false,
          redirect: false
        ] ++ bounded_response_options(opts)
      )
      |> finalize_bounded_response()

    case response do
      {:ok, %{status: 202, body: body}} -> parse_submission(body)
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, error_message(body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Checks route/device reachability without reading or mutating the response body."
  def probe(url, opts \\ []) do
    response =
      Req.head(url,
        receive_timeout: Keyword.get(opts, :request_timeout_ms, @default_timeout),
        retry: false,
        redirect: false
      )

    case response do
      {:ok, %{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  def get_job(url, opts \\ []) do
    response =
      Req.get(
        url,
        [
          receive_timeout: Keyword.get(opts, :request_timeout_ms, @default_timeout),
          retry: false,
          redirect: false
        ] ++ bounded_response_options(opts)
      )
      |> finalize_bounded_response()

    case response do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> decode_json(body)
      {:ok, %{status: status, body: body}} -> {:error, {:http, status, error_message(body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def bounded_response_into(max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    fn {:data, data}, {request, response} ->
      case response.body do
        {:response_too_large, ^max_bytes} ->
          {:halt, {request, response}}

        body ->
          {size, chunks} = bounded_body_state(body)
          next_size = size + byte_size(data)

          if next_size > max_bytes do
            {:halt, {request, %{response | body: {:response_too_large, max_bytes}}}}
          else
            {:cont, {request, %{response | body: {:bounded_response, next_size, [data | chunks]}}}}
          end
      end
    end
  end

  defp bounded_response_options(opts) do
    max_bytes =
      opts
      |> Keyword.get(:max_response_bytes, @max_response_bytes)
      |> max(1)
      |> min(@max_response_bytes)

    [
      raw: true,
      into: bounded_response_into(max_bytes)
    ] ++ test_adapter_options(opts)
  end

  # Req's Plug adapter is used only by the HTTP-client regression tests. The
  # production provisioning call sites never supply this option.
  defp test_adapter_options(opts), do: Keyword.take(opts, [:plug])

  defp bounded_body_state(""), do: {0, []}
  defp bounded_body_state(nil), do: {0, []}
  defp bounded_body_state({:bounded_response, size, chunks}), do: {size, chunks}

  defp finalize_bounded_response({:ok, %{body: {:response_too_large, max_bytes}, status: status}}) do
    {:error, {:response_too_large, status, max_bytes}}
  end

  defp finalize_bounded_response({:ok, %{body: {:bounded_response, _size, chunks}} = response}) do
    {:ok, %{response | body: chunks |> Enum.reverse() |> IO.iodata_to_binary()}}
  end

  defp finalize_bounded_response({:ok, %{body: body}} = response) when body in [nil, ""], do: response
  defp finalize_bounded_response({:ok, _response} = response), do: response
  defp finalize_bounded_response({:error, reason}), do: {:error, {:transport, reason}}

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

  defp error_message(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> error_message(decoded)
      _ -> String.slice(body, 0, 512)
    end
  end

  defp error_message(body), do: inspect(body)
end
