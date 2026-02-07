defmodule NixstasisWeb.ReportLive.FormComponent do
  use NixstasisWeb, :live_component

  alias Nixstasis.Reporting

  @impl true
  def update(%{report: _report} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:report_name, "")
     |> assign(:fields, [%{id: Ecto.UUID.generate(), path: "", alias: ""}])
     |> assign(:filters, [])}
  end

  @impl true
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
      {:ok, report} ->
        notify_parent({:saved, report})

        {:noreply,
         socket
         |> put_flash(:info, "Report created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply, put_flash(socket, :error, "Unable to save report")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to save report")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Define columns and filters for your report.</:subtitle>
      </.header>

      <div class="py-4">
        <form phx-submit="save" phx-change="validate" phx-target={@myself}>
          <div class="mb-6">
            <label class="block text-sm font-medium text-base-content mb-2">Report Name</label>
            <input
              type="text"
              name="name"
              value={@report_name}
              class="input input-bordered w-full"
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
                phx-target={@myself}
                class="btn btn-sm"
              >
                + Add Column
              </button>
            </div>

            <div class="space-y-3">
              <%= for field <- @fields do %>
                <div class="flex gap-4 items-start bg-base-200 p-3 rounded border border-base-300">
                  <div class="flex-1">
                    <label class="block text-xs text-base-content/70 mb-1">JSON Path</label>
                    <input
                      type="text"
                      value={field.path}
                      phx-blur="update_field"
                      phx-target={@myself}
                      phx-value-id={field.id}
                      phx-value-key="path"
                      placeholder="e.g. temp"
                      class="input input-sm input-bordered w-full"
                    />
                  </div>
                  <div class="flex-1">
                    <label class="block text-xs text-base-content/70 mb-1">Column Title</label>
                    <input
                      type="text"
                      value={field.alias}
                      phx-blur="update_field"
                      phx-target={@myself}
                      phx-value-id={field.id}
                      phx-value-key="alias"
                      placeholder="Title"
                      class="input input-sm input-bordered w-full"
                    />
                  </div>
                  <button
                    type="button"
                    phx-click="remove_field"
                    phx-target={@myself}
                    phx-value-id={field.id}
                    class="mt-6 text-error hover:text-error/80"
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
                phx-target={@myself}
                class="btn btn-sm"
              >
                + Add Filter
              </button>
            </div>

            <div class="space-y-3">
              <%= for filter <- @filters do %>
                <div class="flex gap-4 items-start bg-base-200 p-3 rounded border border-base-300">
                  <div class="flex-1">
                    <label class="block text-xs text-base-content/70 mb-1">Field/Path</label>
                    <input
                      type="text"
                      value={filter.field}
                      phx-blur="update_filter"
                      phx-target={@myself}
                      phx-value-id={filter.id}
                      phx-value-key="field"
                      placeholder="path"
                      class="input input-sm input-bordered w-full"
                    />
                  </div>
                  <div class="w-32">
                    <label class="block text-xs text-base-content/70 mb-1">Operator</label>
                    <select
                      phx-blur="update_filter"
                      phx-target={@myself}
                      phx-value-id={filter.id}
                      phx-value-key="operator"
                      class="select select-sm select-bordered w-full"
                    >
                      <option value="=" selected={filter.operator == "="}>=</option>
                      <option value="!=" selected={filter.operator == "!="}>!=</option>
                      <option value=">" selected={filter.operator == ">"}>&gt;</option>
                      <option value="<" selected={filter.operator == "<"}>&lt;</option>
                    </select>
                  </div>
                  <div class="flex-1">
                    <label class="block text-xs text-base-content/70 mb-1">Value</label>
                    <input
                      type="text"
                      value={filter.value}
                      phx-blur="update_filter"
                      phx-target={@myself}
                      phx-value-id={filter.id}
                      phx-value-key="value"
                      class="input input-sm input-bordered w-full"
                    />
                  </div>
                  <button
                    type="button"
                    phx-click="remove_filter"
                    phx-target={@myself}
                    phx-value-id={filter.id}
                    class="mt-6 text-error hover:text-error/80"
                  >
                    <.icon name="hero-trash" class="w-5 h-5" />
                  </button>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex justify-end pt-4 border-t border-base-300">
            <.button phx-disable-with="Saving...">Save Report</.button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
