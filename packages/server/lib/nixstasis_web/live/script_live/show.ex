defmodule NixstasisWeb.ScriptLive.Show do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Scripts
  alias NixstasisWeb.Permissions

  @impl true
  def mount(%{"id" => id}, session, socket) do
    can_view = Permissions.can_view_scripts?(session)
    can_manage = Permissions.can_manage_scripts?(session)
    device_permissions = Permissions.device_permissions(session)

    if can_view do
      draft = Domain.get_script_draft!(id)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Nixstasis.PubSub, "scripts:#{draft.id}")
        Process.send_after(self(), :refresh_script_runs, 3_000)
      end

      devices =
        Devices.list_devices()
        |> filter_visible_devices(device_permissions)

      %{
        versions: versions,
        validation_runs: validation_runs,
        test_runs: test_runs,
        deployment_runs: deployment_runs,
        client_actions: client_actions
      } =
        script_run_assigns(draft)

      rendered = Scripts.render_draft(draft)
      schema = draft.front_matter["schema"] || %{}

      {:ok,
       socket
       |> assign(:page_title, draft.name)
       |> assign(:draft, draft)
       |> assign(:front_matter_yaml, draft.front_matter)
       |> assign(:body, draft.body)
       |> assign(:rendered, rendered)
       |> assign(:devices, devices)
       |> assign(:selected_device_ids, [])
       |> assign(:versions, versions)
       |> assign(:validation_runs, validation_runs)
       |> assign(:test_runs, test_runs)
       |> assign(:deployment_runs, deployment_runs)
       |> assign(:client_actions, client_actions)
       |> assign(:device_permissions, device_permissions)
       |> assign(:validation_result, nil)
       |> assign(:can_view, can_view)
       |> assign(:can_manage, can_manage)
       |> assign(:session, session)
       |> assign(:active_tab, "editor")
       |> assign(:front_matter_open, false)
       |> assign(:front_matter_tab, "preview")
       |> assign(:schema_field_errors, %{})
       |> assign(:schema_fields, schema_to_fields(schema))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Not authorized")
       |> push_navigate(to: ~p"/")}
    end
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
  def handle_info({:script_runs_changed, _draft_id}, socket) do
    {:noreply, refresh_script_runs(socket)}
  end

  def handle_info(:refresh_script_runs, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_script_runs, 3_000)
    {:noreply, refresh_script_runs(socket)}
  end

  @impl true
  def handle_event("update_body", %{"body" => content}, socket) do
    {_front_matter, body} = parse_rendered_content(content)

    front_matter = socket.assigns.front_matter_yaml

    attrs = %{body: body, front_matter: front_matter, name: front_matter["name"]}

    case Scripts.update_draft(session(socket), socket.assigns.draft, attrs) do
      {:ok, updated} ->
        rendered = Scripts.render_draft(updated)

        {:noreply,
         socket
         |> assign(:draft, updated)
         |> assign(:front_matter_yaml, front_matter)
         |> assign(:body, body)
         |> assign(:rendered, rendered)
         |> assign(:schema_fields, schema_to_fields(front_matter["schema"] || %{}))
         |> put_flash(:info, "Script saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save script")}
    end
  end

  def handle_event("validate_script", _params, socket) do
    case Scripts.validate_draft(session(socket), socket.assigns.draft) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign(:validation_runs, [run | socket.assigns.validation_runs])
         |> assign(:versions, list_versions(socket.assigns.draft))
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
    if device_selected?(socket.assigns.device_permissions, device_id) do
      selected = socket.assigns.selected_device_ids

      new_selected =
        if device_id in selected do
          List.delete(selected, device_id)
        else
          [device_id | selected]
        end

      {:noreply, assign(socket, :selected_device_ids, new_selected)}
    else
      {:noreply, put_flash(socket, :error, "Not authorized for this device")}
    end
  end

  def handle_event("queue_test", _params, socket) do
    case {selected_devices(socket), latest_validated_version(socket.assigns.versions)} do
      {[], _version} ->
        {:noreply, put_flash(socket, :error, "Select at least one device")}

      {_devices, nil} ->
        {:noreply, put_flash(socket, :error, "No script version available. Run validation first to create one.")}

      {devices, version} ->
        queue_test(socket, version, devices)
    end
  end

  def handle_event("queue_deployment", _params, socket) do
    devices = selected_devices(socket)

    cond do
      not deploy_ready?(socket.assigns.front_matter_yaml, socket.assigns.versions, socket.assigns.test_runs) ->
        {:noreply, put_flash(socket, :error, "Validate and pass a test before deploying")}

      devices == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one device")}

      true ->
        queue_deployment(socket, latest_validated_version(socket.assigns.versions), devices)
    end
  end

  def handle_event("retry_test", %{"id" => id}, socket) do
    with run when not is_nil(run) <- Enum.find(socket.assigns.test_runs, &(&1.id == id)),
         version when not is_nil(version) <- Enum.find(socket.assigns.versions, &(&1.id == run.script_version_id)),
         devices <-
           Enum.filter(socket.assigns.devices, fn device ->
             device.id in run.target_device_ids and device_selected?(socket.assigns.device_permissions, device.id)
           end),
         false <- devices == [],
         {:ok, _run} <- Scripts.queue_test_run(session(socket), socket.assigns.draft, version, devices) do
      {:noreply, refresh_script_runs(socket) |> put_flash(:info, "Test retry queued")}
    else
      false -> {:noreply, put_flash(socket, :error, "Retry skipped: no authorized target devices")}
      _ -> {:noreply, put_flash(socket, :error, "Failed to retry test")}
    end
  end

  def handle_event("retry_deployment", %{"id" => id}, socket) do
    with run when not is_nil(run) <- Enum.find(socket.assigns.deployment_runs, &(&1.id == id)),
         version when not is_nil(version) <- Enum.find(socket.assigns.versions, &(&1.id == run.script_version_id)),
         devices <-
           Enum.filter(socket.assigns.devices, fn device ->
             device.id in run.target_device_ids and device_selected?(socket.assigns.device_permissions, device.id)
           end),
         false <- devices == [],
         {:ok, _run} <- Scripts.queue_deployment(session(socket), socket.assigns.draft, version, devices) do
      {:noreply, refresh_script_runs(socket) |> put_flash(:info, "Deployment retry queued")}
    else
      false -> {:noreply, put_flash(socket, :error, "Retry skipped: no authorized target devices")}
      _ -> {:noreply, put_flash(socket, :error, "Failed to retry deployment")}
    end
  end

  def handle_event("cancel_test", %{"id" => id}, socket) do
    with run when not is_nil(run) <- Enum.find(socket.assigns.test_runs, &(&1.id == id)),
         {:ok, _run} <- Scripts.cancel_test_run(session(socket), run) do
      {:noreply, refresh_script_runs(socket) |> put_flash(:info, "Test run marked failed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to cancel test run")}
    end
  end

  def handle_event("cancel_deployment", %{"id" => id}, socket) do
    with run when not is_nil(run) <- Enum.find(socket.assigns.deployment_runs, &(&1.id == id)),
         {:ok, _run} <- Scripts.cancel_deployment_run(session(socket), run) do
      {:noreply, refresh_script_runs(socket) |> put_flash(:info, "Deployment marked failed")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to cancel deployment")}
    end
  end

  def handle_event("set_tab", %{"tab" => "deploy"}, socket) do
    if deploy_ready?(socket.assigns.front_matter_yaml, socket.assigns.versions, socket.assigns.test_runs) do
      {:noreply, assign(socket, :active_tab, "deploy")}
    else
      {:noreply, assign(socket, :active_tab, "test")}
    end
  end

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("set_front_matter_tab", %{"tab" => tab}, socket) do
    case tab do
      "schema" -> {:noreply, assign(socket, :front_matter_tab, "schema")}
      _ -> {:noreply, assign(socket, :front_matter_tab, "preview")}
    end
  end

  def handle_event("toggle_front_matter", _params, socket) do
    open = !socket.assigns.front_matter_open

    {:noreply, ensure_front_matter_tab_opened(assign(socket, :front_matter_open, open))}
  end

  def handle_event("update_front_matter_field", %{"key" => key} = params, socket) do
    value = Map.get(params, "value", "")
    current = socket.assigns.front_matter_yaml

    front_matter = Map.put(current, key, value)

    case Scripts.update_draft(session(socket), socket.assigns.draft, %{
           front_matter: front_matter,
           name: front_matter["name"]
         }) do
      {:ok, updated} ->
        rendered = Scripts.render_draft(updated)

        {:noreply,
         socket
         |> assign(:draft, updated)
         |> assign(:front_matter_yaml, front_matter)
         |> assign(:rendered, rendered)
         |> ensure_deploy_tab_active()}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # Schema field handlers — recursive path-based IDs

  def handle_event("add_schema_field", %{"path" => path}, socket) do
    path = String.split(path, ",", trim: true)
    new_field = new_field()

    fields = add_field_at_path(socket.assigns.schema_fields, path, new_field)

    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> save_schema_to_draft()
     |> push_event("focus_schema_field_name", %{id: "sf-name-#{new_field.id}"})}
  end

  def handle_event("add_schema_field", _params, socket) do
    new_field = new_field()
    fields = socket.assigns.schema_fields ++ [new_field]

    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> save_schema_to_draft()
     |> push_event("focus_schema_field_name", %{id: "sf-name-#{new_field.id}"})}
  end

  def handle_event("remove_schema_field", %{"id" => id}, socket) do
    fields =
      remove_field_by_id(socket.assigns.schema_fields, id)
      |> then(fn
        [] -> [new_field()]
        other -> other
      end)

    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> assign(:schema_field_errors, Map.delete(socket.assigns.schema_field_errors, id))
     |> save_schema_to_draft()}
  end

  def handle_event("update_schema_field", %{"_target" => ["schema_fields" | path_parts]} = params, socket) do
    value =
      params
      |> get_in(["schema_fields" | path_parts])
      |> to_string()

    [path, key] = path_parts
    path_list = String.split(path, ",", trim: true)

    fields = update_field_at_path(socket.assigns.schema_fields, path_list, key, value)

    errors =
      if key == "name" and String.trim(value) != "" do
        Map.delete(socket.assigns.schema_field_errors, List.last(path_list))
      else
        socket.assigns.schema_field_errors
      end

    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> assign(:schema_field_errors, errors)
     |> save_schema_to_draft()}
  end

  def handle_event("update_schema_field", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "schema_field_name_keydown",
        %{"id" => id, "key" => "Enter", "value" => value, "level" => level_str},
        socket
      ) do
    fields = update_field_name(socket.assigns.schema_fields, id, value)
    level = String.to_integer(level_str)
    new_field = new_field(level)
    fields = add_field_at_level(fields, id, level, new_field)

    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> assign(:schema_field_errors, Map.delete(socket.assigns.schema_field_errors, id))
     |> save_schema_to_draft()
     |> push_event("focus_schema_field_name", %{id: "sf-name-#{new_field.id}"})}
  end

  def handle_event("schema_field_name_keydown", %{"id" => id, "key" => "Tab", "shift_key" => true}, socket) do
    fields = socket.assigns.schema_fields
    field = find_field_by_id(fields, id)

    if field != nil and (field.level || 0) > 0 and field.name == "" do
      parent_path = find_parent_path(fields, id)
      new_field = new_field()
      fields = add_field_at_path(fields, parent_path, new_field)

      {:noreply,
       socket
       |> assign(:schema_fields, fields)
       |> save_schema_to_draft()
       |> push_event("focus_schema_field_name", %{id: "sf-name-#{new_field.id}"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("schema_field_name_keydown", %{"id" => id, "key" => key, "level" => level_str}, socket)
      when key in ["Backspace", "Delete"] do
    fields = socket.assigns.schema_fields
    _level = String.to_integer(level_str)

    if removable_empty_field?(fields, id) do
      {:noreply, remove_empty_field(socket, fields, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("schema_field_name_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "schema_field_type_keydown",
        %{"id" => field_id, "key" => "Enter", "level" => level_str} = params,
        socket
      ) do
    fields = socket.assigns.schema_fields
    field = find_field_by_id(fields, field_id)
    level = String.to_integer(level_str)
    type = Map.get(params, "value") || (field && field.type) || "string"
    name = Map.get(params, "name_value") || (field && field.name) || ""

    if field == nil or String.trim(name) == "" do
      {:noreply, require_schema_field_name(socket, field_id)}
    else
      fields = fields |> update_field_name(field_id, name) |> update_field_type(field_id, type)
      add_schema_field(socket, fields, field_id, type, level)
    end
  end

  def handle_event("schema_field_type_keydown", _params, socket) do
    {:noreply, socket}
  end

  defp removable_empty_field?(fields, id) do
    length(flatten_fields(fields)) > 1 and match?(%{name: ""}, find_field_by_id(fields, id))
  end

  defp remove_empty_field(socket, fields, id) do
    remaining = remove_field_by_id(fields, id)
    remaining = if remaining == [], do: [new_field()], else: remaining
    focus_id = remaining |> flatten_fields() |> List.last() |> then(&if(&1, do: &1.id))

    socket = socket |> assign(:schema_fields, remaining) |> save_schema_to_draft()
    if focus_id, do: push_event(socket, "focus_schema_field_name", %{id: "sf-name-#{focus_id}"}), else: socket
  end

  defp queue_test(socket, version, devices) do
    draft = socket.assigns.draft

    case Scripts.queue_test_run(session(socket), draft, version, devices) do
      {:ok, _run} ->
        test_runs = Domain.list_script_test_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

        {:noreply,
         socket
         |> assign(:test_runs, test_runs)
         |> assign(:client_actions, list_client_actions(test_runs, socket.assigns.deployment_runs))
         |> put_flash(:info, "Test queued for #{length(devices)} device(s)")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue test: #{inspect(reason)}")}
    end
  end

  defp queue_deployment(socket, nil, _devices) do
    {:noreply, put_flash(socket, :error, "No script version available. Run validation first to create one.")}
  end

  defp queue_deployment(socket, version, devices) do
    draft = socket.assigns.draft

    case Scripts.queue_deployment(session(socket), draft, version, devices) do
      {:ok, _run} ->
        deployment_runs =
          Domain.list_script_deployment_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

        {:noreply,
         socket
         |> assign(:deployment_runs, deployment_runs)
         |> assign(:client_actions, list_client_actions(socket.assigns.test_runs, deployment_runs))
         |> put_flash(:info, "Deployment queued for #{length(devices)} device(s)")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue deployment: #{inspect(reason)}")}
    end
  end

  defp selected_devices(socket) do
    Enum.filter(
      socket.assigns.devices,
      &(&1.id in socket.assigns.selected_device_ids and device_selected?(socket.assigns.device_permissions, &1.id))
    )
  end

  defp require_schema_field_name(socket, field_id) do
    socket
    |> assign(:schema_field_errors, Map.put(socket.assigns.schema_field_errors, field_id, "Required"))
    |> push_event("focus_schema_field_name", %{id: "sf-name-#{field_id}"})
  end

  defp add_schema_field(socket, fields, field_id, "object", level) when level <= 3 do
    new_field = new_field(level + 1)
    finish_adding_schema_field(socket, add_field_at_path(fields, [field_id], new_field), field_id, new_field)
  end

  defp add_schema_field(socket, fields, field_id, _type, level) do
    new_field = new_field(level)
    finish_adding_schema_field(socket, add_field_at_level(fields, field_id, level, new_field), field_id, new_field)
  end

  defp finish_adding_schema_field(socket, fields, field_id, new_field) do
    {:noreply,
     socket
     |> assign(:schema_fields, fields)
     |> assign(:schema_field_errors, Map.delete(socket.assigns.schema_field_errors, field_id))
     |> save_schema_to_draft()
     |> push_event("focus_schema_field_name", %{id: "sf-name-#{new_field.id}"})}
  end

  attr :field, :map, required: true
  attr :parent_path, :any, required: true
  attr :errors, :map, default: %{}

  def schema_field(assigns) do
    field = assigns.field
    parent_path = assigns.parent_path
    path = if parent_path == :root, do: field.id, else: "#{parent_path},#{field.id}"
    level = field.level || 0
    has_children = field.type == "object" and Map.get(field, :children, []) != []
    is_nested = parent_path != :root
    error = Map.get(assigns.errors, field.id)

    indent_class =
      case level do
        0 -> ""
        1 -> "ml-6"
        2 -> "ml-12"
        _ -> "ml-16"
      end

    assigns =
      assigns
      |> assign(:path, path)
      |> assign(:level, level)
      |> assign(:has_children, has_children)
      |> assign(:is_nested, is_nested)
      |> assign(:indent_class, indent_class)
      |> assign(:error, error)

    ~H"""
    <div class={["schema-field-row relative", @indent_class]} data-schema-field-id={@field.id} data-field-level={@level}>
      <div :if={@is_nested} class="absolute left-[-1.5rem] top-0 h-1/2 w-[1.5rem] border-l-2 border-l-primary/30">
        <div class="absolute left-full bottom-0 w-[1.5rem] border-t-2 border-t-primary/30 rounded-tr-lg"></div>
      </div>
      <div class="ui-form-row">
        <div class="flex-1">
          <label class="ui-form-label">Field Name</label>
          <input
            id={"sf-name-#{@field.id}"}
            type="text"
            name={"schema_fields[#{@path}][name]"}
            value={@field.name}
            placeholder="field_name"
            phx-hook="SchemaFieldInput"
            phx-blur="update_schema_field"
            data-field-id={@field.id}
            phx-value-id={@field.id}
            phx-value-key="name"
            data-field-level={@level}
            class={["ui-input-sm font-mono", @error && "input-error"]}
          />
          <p :if={@error} class="mt-1 text-xs font-semibold text-error">
            {@error}
          </p>
        </div>
        <div class="w-40">
          <label class="ui-form-label">Type</label>
          <select
            id={"sf-type-#{@field.id}"}
            name={"schema_fields[#{@path}][type]"}
            phx-hook="SchemaFieldSelect"
            phx-blur="update_schema_field"
            data-field-id={@field.id}
            phx-value-id={@field.id}
            phx-value-key="type"
            data-field-level={@level}
            class="ui-select-sm"
          >
            <option value="string" selected={@field.type == "string"}>string</option>
            <option value="number" selected={@field.type == "number"}>number</option>
            <option value="boolean" selected={@field.type == "boolean"}>boolean</option>
            <option value="array" selected={@field.type == "array"}>array</option>
            <option :if={@level <= 3} value="object" selected={@field.type == "object"}>object</option>
          </select>
        </div>
        <div class="flex gap-1 mt-6">
          <button
            type="button"
            phx-click="remove_schema_field"
            phx-value-id={@field.id}
            class="text-error hover:text-error/80"
            aria-label="Remove field"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="w-4 h-4"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
              />
            </svg>
          </button>
        </div>
      </div>
      <%= if @has_children do %>
        <div class="schema-field-children ml-6 mt-1 space-y-1 border-l-2 border-l-primary/20 pl-3">
          <.schema_field :for={child <- @field.children} field={child} parent_path={@path} errors={@errors} />
        </div>
        <div class="ml-6 mt-1">
          <button
            type="button"
            phx-click="add_schema_field"
            phx-value-path={@path}
            class="btn btn-xs btn-ghost text-primary"
          >
            + Add Child Field
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # Private helpers

  defp ensure_front_matter_tab_opened(socket) do
    if socket.assigns.front_matter_open and is_nil(socket.assigns.front_matter_tab) do
      assign(socket, :front_matter_tab, "preview")
    else
      socket
    end
  end

  defp ensure_deploy_tab_active(socket) do
    if socket.assigns.active_tab == "deploy" and
         not deploy_ready?(socket.assigns.front_matter_yaml, socket.assigns.versions, socket.assigns.test_runs) do
      assign(socket, :active_tab, "test")
    else
      socket
    end
  end

  defp refresh_script_runs(socket) do
    assign(socket, script_run_assigns(socket.assigns.draft))
  end

  defp filter_visible_devices(devices, permissions) do
    case Permissions.authorized_device_ids(permissions) do
      nil -> devices
      ids -> Enum.filter(devices, &MapSet.member?(ids, &1.id))
    end
  end

  defp device_selected?(permissions, device_id) do
    case Permissions.authorized_device_ids(permissions) do
      nil -> true
      ids -> MapSet.member?(ids, device_id)
    end
  end

  defp script_run_assigns(draft) do
    versions = list_versions(draft)

    validation_runs =
      Domain.list_script_validation_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

    test_runs = Domain.list_script_test_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

    deployment_runs =
      Domain.list_script_deployment_runs() |> elem(1) |> Enum.filter(&(&1.script_draft_id == draft.id))

    %{
      versions: versions,
      validation_runs: validation_runs,
      test_runs: test_runs,
      deployment_runs: deployment_runs,
      client_actions: list_client_actions(test_runs, deployment_runs)
    }
  end

  defp list_versions(draft) do
    Domain.list_script_versions()
    |> elem(1)
    |> Enum.filter(&(&1.script_draft_id == draft.id))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp latest_validated_version(versions), do: Enum.find(versions, &(&1.status == :validated))

  defp deploy_ready?(front_matter, versions, test_runs) do
    with version_number when is_binary(version_number) <- Map.get(front_matter, "version"),
         true <- String.trim(version_number) != "",
         %{id: version_id, version: ^version_number} <- latest_validated_version(versions) do
      Enum.any?(test_runs, &(&1.script_version_id == version_id and &1.status == :passed))
    else
      _ -> false
    end
  end

  defp identity_complete?(front_matter) do
    present?(Map.get(front_matter, "name")) and present?(Map.get(front_matter, "version"))
  end

  defp validation_ready?(front_matter, versions) do
    with version_number when is_binary(version_number) <- Map.get(front_matter, "version"),
         true <- String.trim(version_number) != "",
         %{version: ^version_number} <- latest_validated_version(versions) do
      true
    else
      _ -> false
    end
  end

  defp step_class(true), do: "step step-primary"
  defp step_class(false), do: "step"

  defp latest_run([]), do: nil
  defp latest_run(runs), do: Enum.max_by(runs, &run_timestamp/1)

  defp run_timestamp(run) do
    [:completed_at, :started_at, :validated_at, :inserted_at]
    |> Enum.find_value(fn key -> Map.get(run, key) end)
    |> case do
      %DateTime{} = timestamp -> DateTime.to_unix(timestamp, :microsecond)
      _ -> 0
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp list_client_actions(test_runs, deployment_runs) do
    test_ids = MapSet.new(Enum.map(test_runs, & &1.id))
    deployment_ids = MapSet.new(Enum.map(deployment_runs, & &1.id))

    Domain.list_script_client_actions()
    |> elem(1)
    |> Enum.filter(&(&1.script_test_run_id in test_ids or &1.script_deployment_run_id in deployment_ids))
    |> Enum.group_by(fn action -> {action.kind, action.script_test_run_id || action.script_deployment_run_id} end)
  end

  defp client_actions(client_actions, kind, run_id), do: Map.get(client_actions, {kind, run_id}, [])

  defp device_label(devices, id) do
    case Enum.find(devices, &(&1.id == id)) do
      nil -> id
      device -> device.product_name || device.mac_address || id
    end
  end

  defp session(socket) do
    Map.get(socket.assigns, :session, %{})
  end

  defp new_field(level \\ 0) do
    %{id: Ecto.UUID.generate(), name: "", type: "string", children: [], level: level}
  end

  defp schema_to_fields(schema) when is_map(schema) do
    schema_to_fields(schema, 0)
    |> ensure_schema_fields()
  end

  defp schema_to_fields(_), do: [new_field()]

  defp ensure_schema_fields(fields) do
    if fields == [], do: [new_field()], else: fields
  end

  defp schema_to_fields(schema, level) when is_map(schema) do
    properties = schema["properties"] || %{}

    properties
    |> Enum.map(fn {name, definition} ->
      children =
        if definition["type"] == "object" and is_map(definition["properties"]) do
          schema_to_fields(%{"properties" => definition["properties"]}, level + 1)
        else
          []
        end

      %{
        id: Ecto.UUID.generate(),
        name: name,
        type: definition["type"] || "string",
        children: children,
        level: level
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp fields_to_schema(fields) do
    properties =
      fields
      |> Enum.filter(&(&1.name != ""))
      |> Map.new(fn field ->
        definition = %{"type" => field.type}

        definition =
          if field.type == "object" and Map.get(field, :children, []) != [] do
            child_schema = fields_to_schema(field.children)
            Map.merge(definition, %{"properties" => child_schema["properties"], "required" => child_schema["required"]})
          else
            definition
          end

        {field.name, definition}
      end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties)
    }
  end

  defp save_schema_to_draft(socket) do
    draft = socket.assigns.draft

    front_matter = %{
      "name" => socket.assigns.front_matter_yaml["name"],
      "schema" => fields_to_schema(socket.assigns.schema_fields),
      "version" => socket.assigns.front_matter_yaml["version"]
    }

    case Scripts.update_draft(session(socket), draft, %{front_matter: front_matter}) do
      {:ok, updated} ->
        rendered = Scripts.render_draft(updated)

        socket
        |> assign(:draft, updated)
        |> assign(:front_matter_yaml, front_matter)
        |> assign(:rendered, rendered)
        |> push_event("update_front_matter", %{content: render_yaml_string(front_matter)})

      {:error, _reason} ->
        socket
    end
  end

  defp parse_rendered_content(content) do
    trimmed = String.trim_leading(content, "\ufeff")

    if String.starts_with?(trimmed, "---\n") or String.starts_with?(trimmed, "---\r\n") do
      rest = String.replace_prefix(trimmed, "---\r\n", "")
      rest = String.replace_prefix(rest, "---\n", "")

      case String.split(rest, ~r/\r?\n---\r?\n/, parts: 2) do
        [front_yaml, body] -> parse_front_matter(front_yaml, body, content)
        _ -> {nil, content}
      end
    else
      {nil, content}
    end
  end

  defp parse_front_matter(front_yaml, body, content) do
    case YamlElixir.read_from_string(front_yaml) do
      {:ok, front_matter} when is_map(front_matter) -> {front_matter, body}
      _ -> {nil, content}
    end
  end

  defp add_field_at_path(fields, [], new_field), do: fields ++ [new_field]

  defp add_field_at_path(fields, [id], new_field) do
    Enum.map(fields, fn field ->
      cond do
        field.id == id ->
          parent_level = Map.get(field, :level, 0)
          child_field = %{new_field | level: parent_level + 1}
          children = Map.get(field, :children, []) ++ [child_field]
          %{field | children: children, type: "object"}

        Map.get(field, :children, []) != [] ->
          %{field | children: add_field_at_path(field.children, [id], new_field)}

        true ->
          field
      end
    end)
  end

  defp add_field_at_path(fields, [id | rest], new_field) do
    Enum.map(fields, fn field ->
      if field.id == id do
        children = Map.get(field, :children, [])
        %{field | children: add_field_at_path(children, rest, new_field)}
      else
        field
      end
    end)
  end

  defp add_field_at_level(fields, target_id, target_level, new_field) do
    Enum.flat_map(fields, &add_field_next_to(&1, target_id, target_level, new_field))
  end

  defp add_field_next_to(%{id: target_id} = field, target_id, target_level, new_field) do
    [field, %{new_field | level: target_level}]
  end

  defp add_field_next_to(field, target_id, target_level, new_field) do
    children = Map.get(field, :children, [])
    updated_children = add_field_at_level(children, target_id, target_level, new_field)
    if updated_children == children, do: [field], else: [%{field | children: updated_children}]
  end

  defp update_field_at_path(fields, [id], key, value) do
    Enum.map(fields, &update_field(&1, id, key, value))
  end

  defp update_field_at_path(fields, [id | rest], key, value) do
    Enum.map(fields, fn field ->
      if field.id == id do
        children = Map.get(field, :children, [])
        %{field | children: update_field_at_path(children, rest, key, value)}
      else
        field
      end
    end)
  end

  defp update_field(%{id: id} = field, id, "name", value), do: %{field | name: value}
  defp update_field(%{id: id} = field, id, "type", value), do: %{field | type: value}
  defp update_field(field, _id, _key, _value), do: field

  defp remove_field_by_id(fields, id) do
    fields
    |> Enum.reject(&(&1.id == id))
    |> Enum.map(fn field ->
      children = Map.get(field, :children, [])
      if children != [], do: %{field | children: remove_field_by_id(children, id)}, else: field
    end)
  end

  defp find_field_by_id(fields, id), do: Enum.find_value(fields, &find_field(&1, id))
  defp find_field(%{id: id} = field, id), do: field
  defp find_field(field, id), do: find_field_by_id(Map.get(field, :children, []), id)

  defp find_parent_path(fields, id, acc \\ []) do
    Enum.find_value(fields, &find_parent_path_for_field(&1, id, acc))
  end

  defp find_parent_path_for_field(%{id: id}, id, acc), do: acc

  defp find_parent_path_for_field(field, id, acc) do
    find_parent_path(Map.get(field, :children, []), id, acc ++ [field.id])
  end

  defp flatten_fields(fields) do
    Enum.flat_map(fields, fn field ->
      children = Map.get(field, :children, [])
      [field | flatten_fields(children)]
    end)
  end

  defp update_field_name(fields, id, value) do
    Enum.map(fields, fn field ->
      cond do
        field.id == id -> %{field | name: value}
        Map.get(field, :children, []) != [] -> %{field | children: update_field_name(field.children, id, value)}
        true -> field
      end
    end)
  end

  defp update_field_type(fields, id, value) do
    Enum.map(fields, fn field ->
      cond do
        field.id == id -> %{field | type: value}
        Map.get(field, :children, []) != [] -> %{field | children: update_field_type(field.children, id, value)}
        true -> field
      end
    end)
  end

  defp status_badge_class(:draft), do: "badge-neutral"
  defp status_badge_class(:validated), do: "badge-info"
  defp status_badge_class(:running), do: "badge-warning"
  defp status_badge_class(:queued), do: "badge-neutral"
  defp status_badge_class(:acknowledged), do: "badge-success"
  defp status_badge_class(:passed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(:deployed), do: "badge-success"
  defp status_badge_class(:partial), do: "badge-warning"
  defp status_badge_class(:archived), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-neutral"

  def render_yaml_string(map) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn
      {"schema", value} when is_map(value) -> "schema:\n#{yaml_map(value, 1)}"
      {key, value} when is_binary(value) -> "#{key}: #{yaml_scalar(value)}"
      {key, value} when is_list(value) -> "#{key}:\n#{Enum.map_join(value, "\n", &"  - #{yaml_scalar(&1)}")}"
      {key, value} when is_map(value) -> "#{key}:\n#{yaml_map(value, 1)}"
      {key, value} -> "#{key}: #{yaml_scalar(to_string(value))}"
    end)
  end

  def render_yaml_string(_), do: ""

  defp yaml_map(map, indent) do
    prefix = String.duplicate("  ", indent)

    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn
      {key, value} when is_map(value) ->
        "#{prefix}#{key}:\n#{yaml_map(value, indent + 1)}"

      {key, value} when is_list(value) ->
        if value == [] do
          "#{prefix}#{key}: []"
        else
          items = Enum.map_join(value, "\n", &"#{prefix}  - #{yaml_scalar(&1)}")
          "#{prefix}#{key}:\n#{items}"
        end

      {key, value} ->
        "#{prefix}#{key}: #{yaml_scalar(to_string(value))}"
    end)
  end

  defp yaml_scalar(value) when value in ~w(true false yes no on off null), do: "\"#{value}\""
  defp yaml_scalar(value), do: value
end
