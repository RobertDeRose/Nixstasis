defmodule NixstasisWeb.ReportLive.Index do
  use NixstasisWeb, :live_view
  alias Nixstasis.Reporting

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :reports, Reporting.list_custom_reports())}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <div class="mb-8 flex items-center justify-between">
        <h1 class="text-2xl font-bold">Custom Reports</h1>
        <.link navigate={~p"/reports/new"} class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700">
          + Create Report
        </.link>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Source</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Columns</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for report <- @reports do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                  <.link navigate={~p"/reports/#{report.id}"} class="text-blue-600 hover:underline font-medium">
                    {report.name}
                  </.link>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {report.config["source"] || "telemetry"}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {length(report.config["fields"] || [])} columns
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <.link navigate={~p"/reports/#{report.id}"} class="text-indigo-600 hover:text-indigo-900 mr-4">
                    View
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <%= if Enum.empty?(@reports) do %>
          <div class="p-6 text-center text-gray-500">No reports found. Create one to get started.</div>
        <% end %>
      </div>
    </div>
    """
  end
end
