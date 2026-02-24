defmodule NixstasisWeb.LiveDashboard.E2ELogPresenter do
  @moduledoc false

  @html_void_tags MapSet.new(~w(area base br col embed hr img input link meta param source track wbr))
  @html_token_regex ~r/<!--[\s\S]*?-->|<!DOCTYPE[\s\S]*?>|<\/?[a-zA-Z][^>]*>|<[^>\n]*|[^<]+/i
  @metadata_excluded_keys MapSet.new(~w(
                              schema
                              level
                              event
                              run
                              action_data
                              action
                              expect
                              step_id
                              status
                              duration_ms
                              http_status
                              response_type
                              bytes
                              truncated
                              timestamp
                              journey_id
                            ))
  @action_data_body_keys MapSet.new(~w(body_json body_preview))

  def parse_entries(content) do
    {entries, context} =
      content
      |> sanitize_utf8()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reduce({[], summary_context()}, fn line, {acc, ctx} ->
        {entry, next_ctx} = parse_line(line, ctx)

        case entry do
          nil -> {acc, next_ctx}
          value -> {[value | acc], next_ctx}
        end
      end)

    entries =
      entries
      |> Enum.reverse()
      |> number_step_entries()

    case build_summary_entry(context, count_step_entries(entries)) do
      nil -> entries
      summary -> entries ++ [summary]
    end
  end

  defp parse_line(line, context) do
    case decode_json_log_payload(line) do
      {:ok, payload} ->
        parse_json_payload(payload, context)

      :error ->
        {legacy_entry(line), context}
    end
  rescue
    _ ->
      {legacy_entry(line), context}
  end

  defp parse_json_payload(payload, context) do
    case get_string(payload, "schema") do
      "e2e_log.v1" ->
        parse_v1_payload(payload, context)

      schema when schema != "" ->
        {unsupported_entry("Unsupported log schema: #{schema}", payload), context}

      _ ->
        {unsupported_entry("Unsupported log payload (missing schema)", payload), context}
    end
  end

  defp parse_v1_payload(payload, context) do
    level = get_string(payload, "level", "info")
    event = get_string(payload, "event")

    case {level, event} do
      {"journey", "started"} ->
        {nil, track_journey_started(context, payload)}

      {"journey", "completed"} ->
        {nil, track_journey_completed(context, payload)}

      {"step", _} ->
        entry = step_entry(payload)
        {entry, track_step(context, payload)}

      _ ->
        timestamp = get_string(payload, "timestamp")
        {unsupported_entry("Unsupported e2e_log.v1 entry", payload), track_timestamp(context, timestamp)}
    end
  end

  defp step_entry(payload) do
    status = get_string(payload, "status", "info")
    action = first_present([get_string(payload, "step_id"), get_string(payload, "action"), "—"])
    expected = first_present([get_string(payload, "expect"), "—"])
    duration_ms = parse_optional_int(payload["duration_ms"])
    data_panels = step_data_panels(payload)
    metadata = step_metadata(payload)

    base_entry("step", get_string(payload, "timestamp"), status, "STEP")
    |> Map.merge(%{
      duration_ms: duration_ms,
      step_header: %{
        action: action,
        expected: expected,
        status: status
      },
      data_panels: data_panels,
      metadata: metadata,
      metadata_pretty: pretty_map_or_nil(metadata)
    })
  end

  defp legacy_entry(line) do
    unsupported_entry("Unsupported legacy log format (expected e2e_log.v1)", %{
      "raw_line" => sanitize_utf8(line)
    })
  end

  defp unsupported_entry(message, payload) do
    base_entry("info", get_string(payload, "timestamp"), "info", "INFO")
    |> Map.merge(%{
      message: message,
      payload_label: "Raw payload",
      payload_pretty: Jason.encode!(payload, pretty: true)
    })
  end

  defp base_entry(kind, timestamp, status, icon_label) do
    %{
      kind: kind,
      timestamp: timestamp,
      status: status,
      icon_label: icon_label,
      duration_ms: nil,
      step_header: nil,
      data_panels: [],
      metadata: %{},
      metadata_pretty: nil,
      summary: nil,
      message: nil,
      payload_label: nil,
      payload_pretty: nil
    }
  end

  defp step_data_panels(payload) do
    action_data = map_value(payload["action_data"])
    response_type = get_string(payload, "response_type")
    http_status = parse_optional_int(payload["http_status"])
    bytes = parse_optional_int(payload["bytes"])
    truncated = truthy?(payload["truncated"])
    {body_panel, consumed_keys} = response_body_panel(response_type, action_data, http_status, bytes, truncated)
    action_panel = action_data_panel(action_data, consumed_keys)

    [body_panel, action_panel]
    |> Enum.reject(&is_nil/1)
  end

  defp response_body_panel(_response_type, nil, _http_status, _bytes, _truncated), do: {nil, MapSet.new()}

  defp response_body_panel("json_response", action_data, http_status, bytes, truncated) do
    {json_response_panel(action_data, http_status, bytes, truncated), @action_data_body_keys}
  end

  defp response_body_panel("html_response", action_data, http_status, bytes, truncated) do
    {html_response_panel(action_data, http_status, bytes, truncated), MapSet.new(["body_preview"])}
  end

  defp response_body_panel(_response_type, _action_data, _http_status, _bytes, _truncated),
    do: {nil, MapSet.new()}

  defp json_response_panel(action_data, http_status, bytes, truncated) do
    cond do
      not is_nil(action_data["body_json"]) ->
        pretty = Jason.encode!(action_data["body_json"], pretty: true)
        response_panel("JSON Response", pretty, http_status, bytes, truncated)

      is_binary(action_data["body_preview"]) and action_data["body_preview"] != "" ->
        preview = action_data["body_preview"]

        pretty =
          case Jason.decode(preview) do
            {:ok, parsed} -> Jason.encode!(parsed, pretty: true)
            _ -> preview
          end

        response_panel("JSON Response", pretty, http_status, bytes, truncated)

      true ->
        nil
    end
  end

  defp html_response_panel(action_data, http_status, bytes, truncated) do
    case action_data["body_preview"] do
      value when is_binary(value) and value != "" ->
        response_panel("HTML Response", format_html_safely(value), http_status, bytes, truncated)

      _ ->
        nil
    end
  end

  defp action_data_panel(nil, _consumed_keys), do: nil

  defp action_data_panel(action_data, consumed_keys) do
    filtered =
      action_data
      |> Enum.reject(fn {key, value} -> MapSet.member?(consumed_keys, key) or blank?(value) end)
      |> Map.new()

    if map_size(filtered) == 0 do
      nil
    else
      pretty = Jason.encode!(filtered, pretty: true)

      %{
        title: "Action Data",
        panel_type: "action_data",
        pretty: pretty,
        http_status: nil,
        bytes: nil,
        truncated: nil
      }
    end
  end

  defp response_panel(title, pretty, http_status, bytes, truncated) do
    %{
      title: title,
      panel_type: "response",
      pretty: pretty,
      http_status: http_status,
      bytes: bytes,
      truncated: truncated
    }
  end

  defp step_metadata(payload) do
    payload
    |> Enum.reject(fn {key, value} -> MapSet.member?(@metadata_excluded_keys, key) or blank?(value) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp pretty_map_or_nil(value) when is_map(value) and map_size(value) == 0, do: nil
  defp pretty_map_or_nil(value), do: Jason.encode!(value, pretty: true)

  defp summary_context do
    %{
      timeline?: false,
      journey_id: nil,
      first_timestamp: nil,
      first_ms: nil,
      start_timestamp: nil,
      start_ms: nil,
      end_timestamp: nil,
      end_ms: nil,
      last_timestamp: nil,
      last_ms: nil,
      steps_total: 0,
      steps_passed: 0,
      steps_failed: 0,
      steps_duration_ms: 0,
      completed_status: nil,
      completed_duration_ms: nil,
      completed_steps_run: nil,
      completed_steps_passed: nil,
      completed_steps_failed: nil
    }
  end

  defp track_journey_started(context, payload) do
    timestamp = get_string(payload, "timestamp")

    context
    |> Map.put(:timeline?, true)
    |> put_if_nil(:journey_id, blank_to_nil(get_string(payload, "journey_id")))
    |> track_timestamp(timestamp)
    |> put_if_nil(:start_timestamp, blank_to_nil(timestamp))
    |> put_if_nil(:start_ms, parse_timestamp_ms(timestamp))
  end

  defp track_journey_completed(context, payload) do
    timestamp = get_string(payload, "timestamp")

    context
    |> Map.put(:timeline?, true)
    |> put_if_nil(:journey_id, blank_to_nil(get_string(payload, "journey_id")))
    |> track_timestamp(timestamp)
    |> Map.put(:end_timestamp, blank_to_nil(timestamp))
    |> Map.put(:end_ms, parse_timestamp_ms(timestamp))
    |> put_if_present(:completed_status, blank_to_nil(get_string(payload, "status")))
    |> put_if_present(:completed_duration_ms, parse_optional_int(payload["duration_ms"]))
    |> put_if_present(:completed_steps_run, parse_optional_int(payload["steps_run"]))
    |> put_if_present(:completed_steps_passed, parse_optional_int(payload["steps_passed"]))
    |> put_if_present(:completed_steps_failed, parse_optional_int(payload["steps_failed"]))
  end

  defp track_step(context, payload) do
    timestamp = get_string(payload, "timestamp")
    status = get_string(payload, "status")
    duration_ms = parse_optional_int(payload["duration_ms"]) || 0

    context =
      context
      |> Map.put(:timeline?, true)
      |> put_if_nil(:journey_id, blank_to_nil(get_string(payload, "journey_id")))
      |> track_timestamp(timestamp)
      |> Map.put(:end_timestamp, blank_to_nil(timestamp))
      |> Map.put(:end_ms, parse_timestamp_ms(timestamp))
      |> Map.update!(:steps_total, &(&1 + 1))
      |> Map.update!(:steps_duration_ms, &(&1 + duration_ms))

    case status do
      "passed" -> Map.update!(context, :steps_passed, &(&1 + 1))
      "failed" -> Map.update!(context, :steps_failed, &(&1 + 1))
      _ -> context
    end
  end

  defp track_timestamp(context, timestamp) do
    ms = parse_timestamp_ms(timestamp)
    timestamp = blank_to_nil(timestamp)

    context
    |> put_if_nil(:first_timestamp, timestamp)
    |> put_if_nil(:first_ms, ms)
    |> put_if_present(:last_timestamp, timestamp)
    |> put_if_present(:last_ms, ms)
  end

  defp build_summary_entry(%{timeline?: false}, _step_count), do: nil

  defp build_summary_entry(context, _step_count) do
    start_at = context.start_timestamp || context.first_timestamp
    end_at = context.end_timestamp || context.last_timestamp || start_at
    total_duration_ms = summary_total_duration_ms(context, start_at, end_at)
    passed_count = summary_passed_count(context)
    failed_count = summary_failed_count(context)
    total_count = summary_total_count(context, passed_count, failed_count)
    journey_status = summary_status(context, failed_count, total_count)

    if total_count >= 2 do
      base_entry("summary", end_at || "", journey_status, "SUMMARY")
      |> Map.put(:summary, %{
        start_at: start_at,
        end_at: end_at,
        total_duration_ms: total_duration_ms,
        passed_count: passed_count,
        failed_count: failed_count,
        total_count: total_count,
        journey_status: journey_status
      })
    else
      nil
    end
  end

  defp summary_total_duration_ms(context, _start_at, _end_at) do
    start_ms = context.start_ms || context.first_ms
    end_ms = context.end_ms || context.last_ms

    cond do
      is_integer(start_ms) and is_integer(end_ms) and end_ms >= start_ms ->
        end_ms - start_ms

      is_integer(context.completed_duration_ms) ->
        context.completed_duration_ms

      context.steps_duration_ms > 0 ->
        context.steps_duration_ms

      true ->
        nil
    end
  end

  defp summary_passed_count(%{steps_total: total, steps_passed: passed}) when total > 0,
    do: passed

  defp summary_passed_count(%{completed_steps_passed: value}) when is_integer(value), do: value
  defp summary_passed_count(_context), do: 0

  defp summary_failed_count(%{steps_total: total, steps_failed: failed}) when total > 0, do: failed
  defp summary_failed_count(%{completed_steps_failed: value}) when is_integer(value), do: value
  defp summary_failed_count(_context), do: 0

  defp summary_total_count(%{steps_total: total}, _passed, _failed) when total > 0, do: total

  defp summary_total_count(%{completed_steps_run: run_count}, _passed, _failed) when is_integer(run_count),
    do: run_count

  defp summary_total_count(_context, passed, failed), do: passed + failed

  defp summary_status(%{completed_status: completed_status}, failed_count, total_count) do
    cond do
      failed_count > 0 -> "failed"
      is_binary(completed_status) and completed_status != "" -> completed_status
      total_count > 0 -> "passed"
      true -> "info"
    end
  end

  defp number_step_entries(entries) do
    step_count = count_step_entries(entries)

    if step_count <= 1 do
      entries
    else
      width = max(String.length(Integer.to_string(step_count)), 2)

      {numbered, _index} =
        Enum.map_reduce(entries, 0, fn entry, index ->
          number_step_entry(entry, index, width)
        end)

      numbered
    end
  end

  defp number_step_entry(%{kind: "step"} = entry, index, width) do
    next_index = index + 1
    label = "STEP " <> String.pad_leading(Integer.to_string(next_index), width, "0")
    {Map.put(entry, :icon_label, label), next_index}
  end

  defp number_step_entry(entry, index, _width), do: {entry, index}

  defp count_step_entries(entries) do
    Enum.count(entries, &(&1.kind == "step"))
  end

  defp format_html_safely(body) do
    body
    |> normalize_html_boundaries()
    |> String.trim()
    |> format_html()
    |> normalize_html_boundaries()
    |> String.trim()
  rescue
    _ ->
      body
      |> normalize_html_boundaries()
      |> String.trim()
  end

  defp normalize_html_boundaries(body) do
    body
    |> String.replace(~r/-->[ \t]*</, "-->\n<")
    |> String.replace(~r/>[ \t]*<!--/, ">\n<!--")
    |> String.replace(~r/\r\n?/, "\n")
  end

  defp format_html(value) do
    value
    |> String.trim()
    |> then(&Regex.scan(@html_token_regex, &1))
    |> List.flatten()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({0, []}, &format_html_token/2)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp format_html_token(token, {indent, lines}) do
    cond do
      html_closing_tag?(token) ->
        next_indent = max(indent - 1, 0)
        {next_indent, [html_indent(next_indent) <> token | lines]}

      html_comment_or_declaration?(token) ->
        {indent, [html_indent(indent) <> String.trim(token) | lines]}

      html_opening_tag?(token) ->
        next_indent = if html_increases_indent?(token), do: indent + 1, else: indent
        {next_indent, [html_indent(indent) <> token | lines]}

      html_partial_tag?(token) ->
        {indent, [html_indent(indent) <> String.trim(token) | lines]}

      true ->
        append_html_text_token(token, indent, lines)
    end
  end

  defp append_html_text_token(token, indent, lines) do
    case normalize_html_text(token) do
      "" -> {indent, lines}
      text -> {indent, [html_indent(indent) <> text | lines]}
    end
  end

  defp normalize_html_text(token) do
    token
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp html_indent(level), do: String.duplicate("  ", max(level, 0))
  defp html_closing_tag?(token), do: String.starts_with?(token, "</")

  defp html_opening_tag?(token) do
    String.starts_with?(token, "<") and
      String.ends_with?(token, ">") and
      not String.starts_with?(token, "</") and
      not String.starts_with?(token, "<!") and
      not String.starts_with?(token, "<?")
  end

  defp html_partial_tag?(token) do
    String.starts_with?(token, "<") and
      not String.ends_with?(token, ">") and
      not String.starts_with?(token, "</") and
      not String.starts_with?(token, "<!") and
      not String.starts_with?(token, "<?")
  end

  defp html_comment_or_declaration?(token) do
    String.starts_with?(token, "<!--") or
      String.starts_with?(token, "<!") or
      String.starts_with?(token, "<?")
  end

  defp html_increases_indent?(token) do
    not String.ends_with?(token, "/>") and
      not html_void_tag?(token)
  end

  defp html_void_tag?(token) do
    case Regex.run(~r/^<\/?\s*([a-zA-Z0-9:-]+)/, token) do
      [_, tag] -> MapSet.member?(@html_void_tags, String.downcase(tag))
      _ -> false
    end
  end

  defp decode_json_log_payload(line) do
    line
    |> json_decode_candidates()
    |> Enum.find_value(:error, fn candidate ->
      case Jason.decode(candidate) do
        {:ok, %{} = payload} -> {:ok, payload}
        _ -> nil
      end
    end)
  end

  defp json_decode_candidates(line) do
    sanitized = sanitize_utf8(line)

    [sanitized, String.trim(sanitized), slice_json_object(sanitized)]
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp slice_json_object(line) do
    case Regex.run(~r/\{.*\}/s, line) do
      [json] -> json
      _ -> nil
    end
  end

  defp sanitize_utf8(value) when is_binary(value) do
    if String.valid?(value), do: value, else: String.replace_invalid(value, "�")
  end

  defp get_string(map, key, default \\ "")
  defp get_string(nil, _key, default), do: default

  defp get_string(map, key, default) when is_map(map) do
    case Map.get(map, key) do
      nil -> default
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value when is_integer(value) or is_float(value) -> to_string(value)
      true -> "true"
      false -> "false"
      value -> inspect(value)
    end
  end

  defp map_value(value) when is_map(value), do: value
  defp map_value(_), do: nil

  defp parse_optional_int(value) when is_integer(value), do: value

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_optional_int(_), do: nil

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_), do: false

  defp parse_timestamp_ms(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :millisecond)
      _ -> nil
    end
  end

  defp parse_timestamp_ms(_), do: nil

  defp put_if_nil(map, _key, nil), do: map

  defp put_if_nil(map, key, value) do
    if is_nil(map[key]), do: Map.put(map, key, value), else: map
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp first_present(values) do
    Enum.find(values, fn value -> not blank?(value) end) || ""
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(%{} = map), do: map_size(map) == 0
  defp blank?(_), do: false

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
