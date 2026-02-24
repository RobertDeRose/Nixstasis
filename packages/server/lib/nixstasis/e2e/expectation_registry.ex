defmodule Nixstasis.E2E.ExpectationRegistry do
  @moduledoc """
  Validates journey step actions and expectations against the server-side registry.
  """

  @allowed_expectations %{
    "register_device" => MapSet.new(["uuid_returned"]),
    "fetch_dashboard" => MapSet.new(["dashboard_payload"]),
    "create_record" => MapSet.new(["record_created"]),
    "update_record" => MapSet.new(["record_updated"]),
    "logout" => MapSet.new(["session_ended"]),
    "runtime_register_device" => MapSet.new(["runtime_device_registered"]),
    "runtime_check_domain" => MapSet.new(["tls_domain_allowed"]),
    "runtime_approve_device" => MapSet.new(["device_approved"]),
    "runtime_create_alert_rule" => MapSet.new(["alert_rule_created"]),
    "runtime_queue_payload_ref_command" => MapSet.new(["command_payload_available"]),
    "runtime_expect_missing_payload_ref" => MapSet.new(["command_payload_missing"]),
    "runtime_reject_invalid_command_results" => MapSet.new(["command_results_rejected"]),
    "runtime_poll_with_scripts" => MapSet.new(["scripts_polled_under_budget"]),
    "runtime_verify_telemetry" => MapSet.new(["telemetry_persisted"]),
    "runtime_create_report" => MapSet.new(["report_created"]),
    "runtime_verify_report" => MapSet.new(["report_rendered"]),
    "runtime_verify_alert" => MapSet.new(["alert_triggered"]),
    "runtime_cleanup" => MapSet.new(["runtime_resources_cleaned"])
  }

  def validate_journeys(journey_ids) when is_list(journey_ids) do
    journey_ids
    |> Enum.reduce_while(:ok, fn journey_id, _acc ->
      case validate_journey(journey_id) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, {:invalid_action_expectation, message}}}
      end
    end)
  end

  def validate_journeys(_journey_ids), do: {:error, {:invalid_action_expectation, "Journey IDs must be a list."}}

  defp validate_journey(journey_id) do
    with {:ok, steps} <- load_journey_steps(journey_id) do
      validate_steps(journey_id, steps)
    end
  end

  defp validate_steps(_journey_id, []), do: {:error, "Journey has no steps to validate."}

  defp validate_steps(journey_id, steps) do
    Enum.reduce_while(steps, :ok, fn step, _acc ->
      action = Map.get(step, :action)
      expect = Map.get(step, :expect)

      cond do
        blank?(action) ->
          {:halt, {:error, "Journey '#{journey_id}' has a step without an action."}}

        blank?(expect) ->
          {:halt, {:error, "Journey '#{journey_id}' action '#{action}' is missing an expect token."}}

        not Map.has_key?(@allowed_expectations, action) ->
          {:halt, {:error, "Journey '#{journey_id}' action '#{action}' is not supported."}}

        not MapSet.member?(Map.fetch!(@allowed_expectations, action), expect) ->
          {:halt, {:error, "Journey '#{journey_id}' action '#{action}' does not allow expect '#{expect}'."}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp load_journey_steps(journey_id) when is_binary(journey_id) do
    path = Path.join(journey_dir(), "#{journey_id}.yaml")

    case File.read(path) do
      {:ok, content} ->
        {:ok, parse_steps(content)}

      {:error, _reason} ->
        {:error, "Journey file for '#{journey_id}' was not found at #{path}."}
    end
  end

  defp journey_dir do
    Path.expand("../client/scripts/e2e/journeys", File.cwd!())
  end

  defp parse_steps(content) do
    {steps, current_step} =
      content
      |> String.split("\n")
      |> Enum.reduce({[], nil}, &parse_step_line/2)

    steps
    |> append_step_if_present(current_step)
    |> Enum.reverse()
  end

  defp parse_step_line(line, {steps, current_step}) do
    action = parse_line_value(line, ~r/^\s*(?:-\s*)?action:\s*["']?([^"'\n]+)["']?\s*$/)
    expect = parse_line_value(line, ~r/^\s*expect:\s*["']?([^"'\n]+)["']?\s*$/)

    cond do
      is_binary(action) ->
        {append_step_if_present(steps, current_step), %{action: String.trim(action), expect: ""}}

      is_binary(expect) and is_map(current_step) ->
        {steps, %{current_step | expect: String.trim(expect)}}

      true ->
        {steps, current_step}
    end
  end

  defp parse_line_value(line, regex) do
    case Regex.run(regex, line) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp append_step_if_present(steps, nil), do: steps

  defp append_step_if_present(steps, step) do
    if blank?(step.action) do
      steps
    else
      [step | steps]
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false
end
