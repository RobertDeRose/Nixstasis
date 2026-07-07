defmodule NixstasisWeb.CommandPolicyLive.CategoryFormComponent do
  use NixstasisWeb, :live_component

  alias Nixstasis.CommandAllowlists.Audit
  alias Nixstasis.CommandAllowlists.Category
  alias Nixstasis.Domain

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>{@title}</.header>
      <.simple_form
        for={@form}
        as={:category}
        id="category-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:display_name]} type="text" label="Display Name" />
        <.input field={@form[:description]} type="text" label="Description" />
        <:actions><.button phx-disable-with="Saving...">Save Category</.button></:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{category: category} = assigns, socket) do
    form =
      if category[:id] do
        AshPhoenix.Form.for_update(category, :update, domain: Domain, params: form_params(category))
      else
        AshPhoenix.Form.for_create(Category, :create, domain: Domain, params: %{})
      end

    {:ok, socket |> assign(assigns) |> assign_form(form)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    category_params = params["category"] || params["form"] || %{}
    {:noreply, assign_form(socket, AshPhoenix.Form.validate(socket.assigns.form, category_params))}
  end

  def handle_event("save", params, socket) do
    category_params = params["category"] || params["form"] || %{}

    case AshPhoenix.Form.submit(socket.assigns.form, params: category_params) do
      {:ok, category} ->
        Audit.emit(audit_action(socket.assigns.action), %{category_id: category.id, slug: category.slug})
        notify_parent({:category_saved, category})
        {:noreply, push_patch(socket, to: socket.assigns.patch)}

      {:error, form} ->
        {:noreply, assign_form(socket, form)}
    end
  end

  defp audit_action(:edit_category), do: :category_updated
  defp audit_action(_), do: :category_created

  defp form_params(category) do
    %{"slug" => category.slug, "display_name" => category.display_name, "description" => category.description}
  end

  defp assign_form(socket, %Phoenix.HTML.Form{} = form), do: assign(socket, :form, form)
  defp assign_form(socket, form), do: assign(socket, :form, to_form(form))
  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
