defmodule NixstasisWeb.ScriptLive.Show do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Scripts
  alias NixstasisWeb.Permissions

  @impl true
  def mount(%{"id" => id}, session, socket) do
    permissions = Permissions.script_permissions(session)
    can_manage = Permissions.can_manage_scripts?(permissions)

    draft = Domain.get_script_draft!(id)
    devices = Devices.list_devices()
    versions = Domain.list_script_versions() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))
    validation_runs = Domain.list_script_validation_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))
    test_runs = Domain.list_script_test_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))
    deployment_runs = Domain.list_script_deployment_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

    rendered = Scripts.render_draft(draft)

    {:ok,
     socket
     |> assign(:page_title, draft.name)
     |> assign(:draft, draft)
     |> assign(:front_matter_yaml, YamlElixir.read_from_string!(rendered) |> Map.get("front_matter", %{}))
     |> assign(:body, draft.body)
     |> assign(:rendered, rendered)
     |> assign(:devices, devices)
     |> assign(:selected_device_ids, [])
     |> assign(:versions, versions)
     |> assign(:validation_runs, validation_runs)
     |> assign(:test_runs, test_runs)
     |> assign(:deployment_runs, deployment_runs)
     |> assign(:validation_result, nil)
     |> assign(:can_manage, can_manage)
     |> assign(:active_tab, "editor")}
  rescue
    _ ->
      {:ok,
       socket
       |> put_flash(:error, "Script not found")
       |> push_navigate(to: ~p"/scripts")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_body", %{"body" => body}, socket) do
    draft = socket.assigns.draft

    case Scripts.update_draft(session(socket), draft, %{body: body}) do
      {:ok, updated} ->
        rendered = Scripts.render_draft(updated)

        {:noreply,
         socket
         |> assign(:draft, updated)
         |> assign(:body, body)
         |> assign(:rendered, rendered)
         |> put_flash(:info, "Script saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save script")}
    end
  end

  def handle_event("update_front_matter", %{"front_matter" => fm_params}, socket) do
    draft = socket.assigns.draft
    front_matter = %{"name" => fm_params["name"], "schema" => decode_schema(fm_params["schema"]), "version" => fm_params["version"]}

    case Scripts.update_draft(session(socket), draft, %{front_matter: front_matter, name: fm_params["name"]}) do
      {:ok, updated} ->
        rendered = Scripts.render_draft(updated)

        {:noreply,
         socket
         |> assign(:draft, updated)
         |> assign(:front_matter_yaml, front_matter)
         |> assign(:rendered, rendered)
         |> put_flash(:info, "Front matter saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save front matter")}
    end
  end

  def handle_event("validate_script", _params, socket) do
    case Scripts.validate_draft(session(socket), socket.assigns.draft) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign(:validation_runs, [run | socket.assigns.validation_runs])
         |> assign(:validation_result, %{status: :passed, run: run})
         |> put_flash(:info, "Validation passed")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:validation_result, %{status: :failed, reason: reason})
         |> put_flash(:error, "Validation failed: #{reason}")}
    end
  end

  def handle_event("toggle_device", %{"device_id" => device_id}, socket) do
    selected = socket.assigns.selected_device_ids

    new_selected =
      if device_id in selected do
        List.delete(selected, device_id)
      else
        [device_id | selected]
      end

    {:noreply, assign(socket, :selected_device_ids, new_selected)}
  end

  def handle_event("queue_test", _params, socket) do
    draft = socket.assigns.draft
    selected_devices = Enum.filter(socket.assigns.devices, &(&1.id in socket.assigns.selected_device_ids))

    if selected_devices == [] do
      {:noreply, put_flash(socket, :error, "Select at least one device")}
    else
      version = List.first(socket.assigns.versions)

      if is_nil(version) do
        {:noreply, put_flash(socket, :error, "No script version available")}
      else
        case Scripts.queue_test_run(session(socket), draft, version, selected_devices) do
          {:ok, _run} ->
            test_runs = Domain.list_script_test_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))


            {:noreply,
             socket
             |> assign(:test_runs, test_runs)
             |> put_flash(:info, "Test queued for #{length(selected_devices)} device(s)")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to queue test: #{inspect(reason)}")}
        end
      end
    end
  end

  def handle_event("queue_deployment", _params, socket) do
    draft = socket.assigns.draft
    selected_devices = Enum.filter(socket.assigns.devices, &(&1.id in socket.assigns.selected_device_ids))

    if selected_devices == [] do
      {:noreply, put_flash(socket, :error, "Select at least one device")}
    else
      version = List.first(socket.assigns.versions)

      if is_nil(version) do
        {:noreply, put_flash(socket, :error, "No script version available")}
      else
        case Scripts.queue_deployment(session(socket), draft, version, selected_devices) do
          {:ok, _run} ->
            deployment_runs = Domain.list_script_deployment_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

            {:noreply,
             socket
             |> assign(:deployment_runs, deployment_runs)
             |> put_flash(:info, "Deployment queued for #{length(selected_devices)} device(s)")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to queue deployment: #{inspect(reason)}")}
        end
      end
    end
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  defp session(socket) do
    Map.get(socket.assigns, :session, %{})
  end

  defp decode_schema(schema_str) when is_binary(schema_str) do
    case YamlElixir.read_from_string(schema_str) do
      {:ok, map} when is_map(map) -> map
      _ -> %{"type" => "object"}
    end
  end

  defp decode_schema(_), do: %{"type" => "object"}

  defp status_badge_class(:draft), do: "badge-neutral"
  defp status_badge_class(:validated), do: "badge-info"
  defp status_badge_class(:running), do: "badge-warning"
  defp status_badge_class(:passed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(:deployed), do: "badge-success"
  defp status_badge_class(:partial), do: "badge-warning"
  defp status_badge_class(:archived), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"
end
