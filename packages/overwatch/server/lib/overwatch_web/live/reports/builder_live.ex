defmodule NixstasisWeb.ReportLive.Builder do
  use NixstasisWeb, :live_view
  alias Nixstasis.Reporting
  alias Nixstasis.Reporting.CustomReport

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:report_name, "")
     |> assign(:fields, [%{id: Ecto.UUID.generate(), path: "", alias: ""}])
     |> assign(:filters, [])
     |> assign(:changeset, Reporting.change_custom_report(%CustomReport{}))}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, :report_name, name)}
  end

  def handle_event("add_field", _, socket) do
    fields = socket.assigns.fields ++ [%{id: Ecto.UUID.generate(), path: "", alias: ""}]
    {:noreply, assign(socket, :fields, fields)}
  end

  def handle_event("remove_field", %{"id" => id}, socket) do
    fields = Enum.reject(socket.assigns.fields, &(&1.id == id))
    {:noreply, assign(socket, :fields, fields)}
  end

  def handle_event("update_field", %{"id" => id, "key" => key, "value" => value}, socket) do
    fields =
      Enum.map(socket.assigns.fields, fn f ->
        if f.id == id, do: Map.put(f, String.to_existing_atom(key), value), else: f
      end)

    {:noreply, assign(socket, :fields, fields)}
  end

  def handle_event("add_filter", _, socket) do
    filters =
      socket.assigns.filters ++
        [%{id: Ecto.UUID.generate(), field: "", operator: "=", value: ""}]

    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("remove_filter", %{"id" => id}, socket) do
    filters = Enum.reject(socket.assigns.filters, &(&1.id == id))
    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("update_filter", %{"id" => id, "key" => key, "value" => value}, socket) do
    filters =
      Enum.map(socket.assigns.filters, fn f ->
        if f.id == id, do: Map.put(f, String.to_existing_atom(key), value), else: f
      end)

    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("save", %{"name" => name}, socket) do
    config = %{
      source: "telemetry",
      fields: Enum.map(socket.assigns.fields, &Map.take(&1, [:path, :alias])),
      filters: Enum.map(socket.assigns.filters, &Map.take(&1, [:field, :operator, :value]))
    }

    report_params = %{
      "name" => name,
      "config" => config
    }

    case Reporting.create_custom_report(report_params) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Report created successfully")
         |> push_navigate(to: ~p"/reports")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl">
      <div class="mb-8 flex items-center justify-between">
        <h1 class="text-2xl font-bold">Build Custom Report</h1>
        <.link navigate={~p"/reports"} class="text-blue-600 hover:underline">
          Cancel
        </.link>
      </div>

      <div class="bg-white p-6 rounded-lg shadow mb-8">
        <form phx-submit="save" phx-change="validate">
          <div class="mb-6">
            <label class="block text-sm font-medium text-gray-700 mb-2">Report Name</label>
            <input
              type="text"
              name="name"
              value={@report_name}
              class="w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
              placeholder="e.g. Daily Temperature Check"
              required
            />
          </div>

    <!-- Fields Section -->
          <div class="mb-8">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">Columns (Fields)</h2>
              <button
                type="button"
                phx-click="add_field"
                class="px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md text-sm text-gray-700"
              >
                + Add Column
              </button>
            </div>

            <div class="space-y-3">
              <%= for field <- @fields do %>
                <div class="flex gap-4 items-start bg-gray-50 p-3 rounded border">
                  <div class="flex-1">
                    <label class="block text-xs text-gray-500 mb-1">JSON Path (e.g. temp)</label>
                    <input
                      type="text"
                      value={field.path}
                      phx-blur="update_field"
                      phx-value-id={field.id}
                      phx-value-key="path"
                      class="w-full text-sm border-gray-300 rounded"
                    />
                  </div>
                  <div class="flex-1">
                    <label class="block text-xs text-gray-500 mb-1">Column Title</label>
                    <input
                      type="text"
                      value={field.alias}
                      phx-blur="update_field"
                      phx-value-id={field.id}
                      phx-value-key="alias"
                      class="w-full text-sm border-gray-300 rounded"
                    />
                  </div>
                  <button
                    type="button"
                    phx-click="remove_field"
                    phx-value-id={field.id}
                    class="mt-6 text-red-600 hover:text-red-800"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              <% end %>
            </div>
          </div>

    <!-- Filters Section -->
          <div class="mb-8">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold">Filters (Optional)</h2>
              <button
                type="button"
                phx-click="add_filter"
                class="px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md text-sm text-gray-700"
              >
                + Add Filter
              </button>
            </div>

            <div class="space-y-3">
              <%= for filter <- @filters do %>
                <div class="flex gap-4 items-start bg-gray-50 p-3 rounded border">
                  <div class="flex-1">
                    <label class="block text-xs text-gray-500 mb-1">Field/Path</label>
                    <input
                      type="text"
                      value={filter.field}
                      phx-blur="update_filter"
                      phx-value-id={filter.id}
                      phx-value-key="field"
                      placeholder="device_id or temp"
                      class="w-full text-sm border-gray-300 rounded"
                    />
                  </div>
                  <div class="w-32">
                    <label class="block text-xs text-gray-500 mb-1">Operator</label>
                    <select
                      phx-blur="update_filter"
                      phx-value-id={filter.id}
                      phx-value-key="operator"
                      class="w-full text-sm border-gray-300 rounded"
                    >
                      <option value="=" selected={filter.operator == "="}>=</option>
                      <option value="!=" selected={filter.operator == "!="}>!=</option>
                      <option value=">" selected={filter.operator == ">"}>&gt;</option>
                      <option value="<" selected={filter.operator == "<"}>&lt;</option>
                    </select>
                  </div>
                  <div class="flex-1">
                    <label class="block text-xs text-gray-500 mb-1">Value</label>
                    <input
                      type="text"
                      value={filter.value}
                      phx-blur="update_filter"
                      phx-value-id={filter.id}
                      phx-value-key="value"
                      class="w-full text-sm border-gray-300 rounded"
                    />
                  </div>
                  <button
                    type="button"
                    phx-click="remove_filter"
                    phx-value-id={filter.id}
                    class="mt-6 text-red-600 hover:text-red-800"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex justify-end pt-4 border-t">
            <button
              type="submit"
              class="px-6 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 shadow-sm"
            >
              Save Report
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
