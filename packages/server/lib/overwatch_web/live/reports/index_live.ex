defmodule NixstasisWeb.ReportLive.Index do
  use NixstasisWeb, :live_view
  alias Nixstasis.Reporting
  alias Nixstasis.Reporting.CustomReport

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :reports, visible_reports())}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Report")
    |> assign(:report, %CustomReport{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Custom Reports")
    |> assign(:report, nil)
  end

  def handle_info({NixstasisWeb.ReportLive.FormComponent, {:saved, report}}, socket) do
    # In a real app with streams we would stream_insert
    # Since we are using a list for now, we prepend and re-assign
    # Or just re-fetch
    reports =
      if e2e_report?(report) do
        socket.assigns.reports
      else
        [report | socket.assigns.reports]
      end

    {:noreply, assign(socket, :reports, reports)}
  end

  defp visible_reports do
    Reporting.list_custom_reports()
    |> Enum.reject(&e2e_report?/1)
  end

  defp e2e_report?(report) do
    source = report.config["source"] || report.config[:source]
    source == "e2e"
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl">
      <.header>
        Custom Reports
        <:actions>
          <.link patch={~p"/reports/new"}>
            <.button>Create Report</.button>
          </.link>
        </:actions>
      </.header>

      <.table id="reports" rows={@reports}>
        <:col :let={report} label="Name">
          <.link navigate={~p"/reports/#{report.id}"} class="link link-primary font-bold">
            {report.name}
          </.link>
        </:col>
        <:col :let={report} label="Source">
          {report.config["source"] || "telemetry"}
        </:col>
        <:col :let={report} label="Columns">
          {length(report.config["fields"] || [])} columns
        </:col>
        <:action :let={report}>
          <.link navigate={~p"/reports/#{report.id}"} class="btn btn-sm btn-ghost">
            View
          </.link>
        </:action>
      </.table>

      <%= if Enum.empty?(@reports) do %>
        <div class="p-6 text-center text-gray-500">
          No reports found. Create one to get started.
        </div>
      <% end %>

      <.modal :if={@live_action == :new} id="report-modal" show on_cancel={JS.patch(~p"/reports")}>
        <.live_component
          module={NixstasisWeb.ReportLive.FormComponent}
          id={@report.id || :new}
          title={@page_title}
          action={@live_action}
          report={@report}
          patch={~p"/reports"}
        />
      </.modal>
    </div>
    """
  end
end
