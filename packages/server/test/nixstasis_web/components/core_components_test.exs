defmodule NixstasisWeb.CoreComponentsTest do
  use NixstasisWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component
  import NixstasisWeb.CoreComponents

  test "flash renders toast with correct positioning classes" do
    assigns = %{flash: %{"info" => "Success message"}, kind: :info}

    html =
      rendered_to_string(~H"""
      <.flash kind={@kind} flash={@flash} />
      """)

    assert html =~ "toast"
    assert html =~ "toast-top"
    assert html =~ "toast-end"
    assert html =~ "Success message"
    assert html =~ "alert-info"
  end

  test "flash error renders correct classes" do
    assigns = %{flash: %{"error" => "Error message"}, kind: :error}

    html =
      rendered_to_string(~H"""
      <.flash kind={@kind} flash={@flash} />
      """)

    assert html =~ "alert-error"
    assert html =~ "Error message"
  end

  test "button preserves its native type attribute" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.button type="submit">Save</.button>
      """)

    assert html =~ ~s(type="submit")
  end

  test "modal exposes its initial focus target" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.modal id="discard-modal" show focus_target="discard-keep">
        <button id="discard-keep">Keep editing</button>
      </.modal>
      """)

    assert html =~ ~s(data-focus-target="discard-keep")
    assert html =~ "modal-dialog"
  end

  test "modal moves focus in, traps it, and returns it on close" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.modal id="discard-modal" show focus_target="discard-keep">
        <button id="discard-keep">Keep editing</button>
      </.modal>
      """)

    modal = html |> LazyHTML.from_fragment() |> LazyHTML.query("#discard-modal")
    [mounted] = LazyHTML.attribute(modal, "phx-mounted")

    assert List.last(js_ops(mounted)) == "focus"
    assert mounted =~ "#discard-keep"
    assert LazyHTML.attribute(modal, "phx-hook") == ["ModalFocus"]
    # The trap wraps the dialog, which must not be focusable itself, or Shift+Tab
    # from a click on its blank space leaves the trap.
    dialog = LazyHTML.query(modal, "[role='dialog']")
    assert LazyHTML.attribute(dialog, "phx-hook") == ["Phoenix.FocusWrap"]
    assert LazyHTML.attribute(dialog, "tabindex") == []
  end

  # The command names in an encoded Phoenix.LiveView.JS attribute, in order.
  defp js_ops(encoded), do: encoded |> Jason.decode!() |> Enum.map(&hd/1)

  test "confirm modal is labelled and starts on Cancel" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.confirm_modal
        id="delete-thing"
        title="Delete Thing"
        on_confirm={Phoenix.LiveView.JS.push("delete")}
        on_cancel={Phoenix.LiveView.JS.push("cancel")}
      >
        Delete the thing?
      </.confirm_modal>
      """)

    assert html =~ ~s(aria-labelledby="delete-thing-title")
    assert html =~ ~s(id="delete-thing-title")
    assert html =~ ~s(data-focus-target="delete-thing-cancel")
    assert html =~ "This action cannot be undone."
  end
end
