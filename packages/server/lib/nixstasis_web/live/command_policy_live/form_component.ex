defmodule NixstasisWeb.CommandPolicyLive.FormComponent do
  use NixstasisWeb, :live_component

  alias Nixstasis.CommandAllowlists.Audit
  alias Nixstasis.CommandAllowlists.CommandEntry
  alias Nixstasis.Domain

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Manage command names, absolute paths, and category tags.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        as={:command_entry}
        id="command-entry-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Command Name" />
        <.input field={@form[:command_path]} type="text" label="Absolute Path" />
        <.input field={@form[:description]} type="text" label="Description" />
        <.input
          field={@form[:category_ids]}
          type="select"
          label="Categories"
          multiple
          options={Enum.map(@categories, &{&1.display_name, &1.id})}
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Command Entry</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{entry: entry} = assigns, socket) do
    form =
      if entry[:id] do
        entry
        |> AshPhoenix.Form.for_update(:update, domain: Domain, forms: [auto?: false], params: form_params(entry))
      else
        CommandEntry
        |> AshPhoenix.Form.for_create(:create, domain: Domain, forms: [auto?: false], params: %{})
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:categories, Domain.list_command_allowlist_categories() |> elem(1))
     |> assign_form(form)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    entry_params = params["command_entry"] || params["form"] || %{}
    form = AshPhoenix.Form.validate(socket.assigns.form, entry_params)
    {:noreply, assign_form(socket, form)}
  end

  def handle_event("save", params, socket) do
    if socket.assigns.can_manage do
      entry_params = params["command_entry"] || params["form"] || %{}

      case AshPhoenix.Form.submit(socket.assigns.form, params: Map.delete(entry_params, "category_ids")) do
        {:ok, entry} -> handle_saved_entry(socket, entry, entry_params["category_ids"] || [])
        {:error, form} -> {:noreply, assign_form(socket, form)}
      end
    else
      {:noreply, socket |> put_flash(:error, "Not authorized") |> push_patch(to: socket.assigns.patch)}
    end
  end

  defp handle_saved_entry(socket, entry, category_ids) do
    case replace_categories(entry.id, category_ids) do
      :ok ->
        Audit.emit(audit_action(socket.assigns.action), %{command_entry_id: entry.id, name: entry.name})
        notify_parent({:saved, entry})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to update categories")}
    end
  end

  defp audit_action(:edit), do: :command_entry_updated
  defp audit_action(_), do: :command_entry_created

  defp replace_categories(entry_id, category_ids) do
    existing =
      Domain.list_command_allowlist_entry_categories()
      |> elem(1)
      |> Enum.filter(&(&1.command_entry_id == entry_id))

    existing_ids = MapSet.new(Enum.map(existing, & &1.category_id))
    wanted_ids = MapSet.new(Enum.filter(category_ids, &is_binary/1))

    removals = Enum.filter(existing, &(not MapSet.member?(wanted_ids, &1.category_id)))
    additions = MapSet.difference(wanted_ids, existing_ids) |> Enum.to_list()

    with :ok <- remove_categories(removals) do
      add_categories(entry_id, additions)
    end
  end

  defp remove_categories(removals) do
    Enum.reduce_while(removals, :ok, fn join, :ok ->
      case Domain.destroy_command_allowlist_entry_category(join) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :destroy_failed}}
      end
    end)
  end

  defp add_categories(entry_id, additions) do
    Enum.reduce_while(additions, :ok, fn category_id, :ok ->
      case Domain.create_command_allowlist_entry_category(%{
             command_entry_id: entry_id,
             category_id: category_id
           }) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :create_failed}}
      end
    end)
  end

  defp form_params(entry) do
    category_ids =
      Domain.list_command_allowlist_entry_categories()
      |> elem(1)
      |> Enum.filter(&(&1.command_entry_id == entry.id))
      |> Enum.map(& &1.category_id)

    %{
      "name" => entry.name,
      "command_path" => entry.command_path,
      "description" => entry.description,
      "category_ids" => category_ids
    }
  end

  defp assign_form(socket, %Phoenix.HTML.Form{} = form), do: assign(socket, :form, form)
  defp assign_form(socket, form), do: assign(socket, :form, to_form(form))
  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
