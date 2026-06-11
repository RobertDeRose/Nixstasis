defmodule NixstasisWeb.ScriptLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Scripts
  alias NixstasisWeb.Permissions

  @impl true
  def mount(_params, session, socket) do
    permissions = Permissions.script_permissions(session)
    can_manage = Permissions.can_manage_scripts?(permissions)

    {:ok,
     socket
     |> assign(:page_title, "Scripts")
     |> assign(:scripts, Scripts.list_drafts() |> elem(1))
     |> assign(:can_manage, can_manage)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    scripts = Scripts.list_drafts() |> elem(1)
    {:noreply, assign(socket, :scripts, scripts)}
  end

  @impl true
  def handle_event("create_script", _params, socket) do
    if socket.assigns.can_manage do
      case Scripts.create_draft(session(socket), %{
             name: "new-script",
             front_matter: %{"name" => "new-script", "schema" => %{"type" => "object"}},
             body: "def main():\n    return {}\n"
           }) do
        {:ok, draft} ->
          {:noreply, push_navigate(socket, to: ~p"/scripts/#{draft.id}")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create script")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  def handle_event("archive_script", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      draft = Enum.find(socket.assigns.scripts, &(&1.id == id))

      case Scripts.archive_draft(session(socket), draft) do
        {:ok, _archived} ->
          scripts = Scripts.list_drafts() |> elem(1)
          {:noreply, assign(socket, :scripts, scripts) |> put_flash(:info, "Script archived")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to archive script")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  defp session(socket) do
    Map.get(socket.assigns, :session, %{})
  end

  defp status_badge_class(:draft), do: "badge-neutral"
  defp status_badge_class(:validated), do: "badge-info"
  defp status_badge_class(:archived), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"
end
