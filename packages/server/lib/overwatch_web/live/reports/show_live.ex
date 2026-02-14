defmodule NixstasisWeb.ReportLive.Show do
  use NixstasisWeb, :live_view
  alias Nixstasis.Reporting
  alias Nixstasis.Reporting.QueryBuilder
  alias Nixstasis.Repo

  def mount(%{"id" => id}, _session, socket) do
    report = Reporting.get_custom_report!(id)

    if e2e_report?(report) do
      {:ok,
       socket
       |> put_flash(:error, "E2E internal reports are not available in this view.")
       |> push_navigate(to: ~p"/reports")}
    else
      # Execute the query
      query = QueryBuilder.build(report.config)
      results = Repo.all(query)

      fields = QueryBuilder.fields_for_report(report.config)
      source = report.config["source"] || report.config[:source] || "telemetry"

      {:ok,
       socket
       |> assign(:report, report)
       |> assign(:results, results)
       |> assign(:fields, fields)
       |> assign(:source, source)}
    end
  end

  defp e2e_report?(report) do
    source = report.config["source"] || report.config[:source]
    source == "e2e"
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-8 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@report.name}</h1>
          <p class="text-sm text-gray-500">Source: {@source}</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/reports"} class="px-4 py-2 border rounded hover:bg-gray-50">
            Back to List
          </.link>
          <!-- TODO: Edit report -->
        </div>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <%= for field <- @fields do %>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {field["alias"] || field["path"]}
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for row <- @results do %>
              <tr>
                <%= for field <- @fields do %>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {Map.get(row, field["alias"] || field["path"])}
                  </td>
                <% end %>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if Enum.empty?(@results) do %>
          <div class="p-6 text-center text-gray-500">No data found matching report criteria.</div>
        <% end %>
      </div>
    </div>
    """
  end
end
