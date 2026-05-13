defmodule NixstasisWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  def render("error.json", %{error: %Ash.Error.Invalid{} = error}) do
    fields = safe_field_errors(error)

    if fields == %{} do
      %{errors: %{detail: "Invalid request"}}
    else
      %{errors: fields}
    end
  end

  def render("error.json", %{error: %Ash.Error.Unknown{}}) do
    %{errors: %{detail: "Internal Server Error"}}
  end

  def render("error.json", _assigns), do: %{errors: %{detail: "Internal Server Error"}}

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  defp safe_field_errors(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.flat_map(&extract_field_messages/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp extract_field_messages(%Ash.Error.Changes.InvalidAttribute{field: field, message: message, vars: vars})
       when is_atom(field) and is_binary(message) do
    [{field, interpolate_message(message, vars)}]
  end

  defp extract_field_messages(%Ash.Error.Changes.Required{field: field}) when is_atom(field) do
    [{field, "is required"}]
  end

  defp extract_field_messages(_error), do: []

  defp interpolate_message(message, vars) when is_map(vars) do
    Enum.reduce(vars, message, fn {key, val}, acc ->
      String.replace(acc, "%{#{key}}", to_string(val))
    end)
  end

  defp interpolate_message(message, _vars), do: message
end
