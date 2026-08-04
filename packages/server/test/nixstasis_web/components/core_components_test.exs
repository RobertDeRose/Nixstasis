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
end
