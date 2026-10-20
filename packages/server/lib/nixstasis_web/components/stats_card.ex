defmodule NixstasisWeb.Components.StatsCard do
  @moduledoc """
  UI component for dashboard stats cards, each linking to the page that deals with its count.
  """

  use Phoenix.Component

  import NixstasisWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a dashboard statistic as a card that links to `navigate`.

  The `tone` colours the top band and icon; `emphasize` also colours the value,
  for counts that need attention.

  ## Examples

      <.stats_card
        navigate={~p"/alerts?status=active"}
        title="Active Alerts"
        value="3"
        icon="hero-bell-alert"
        tone={:error}
        emphasize
      />
  """
  attr(:navigate, :string, required: true, doc: "the page that deals with this count")
  attr(:title, :string, required: true)
  attr(:value, :string, required: true)
  attr(:desc, :string, default: nil)
  attr(:icon, :string, required: true)
  attr(:tone, :atom, values: [:primary, :success, :warning, :error], default: :primary)
  attr(:emphasize, :boolean, default: false, doc: "colour the value in the card's tone when it needs attention")

  def stats_card(assigns) do
    ~H"""
    <.link navigate={@navigate} class="block h-full rounded-box">
      <div class={[
        "stats h-full w-full border border-t-4 border-base-300 bg-base-100 shadow transition-colors hover:border-x-primary hover:border-b-primary",
        tone_classes(@tone).band
      ]}>
        <div class="stat">
          <div class={["stat-figure rounded-full p-2", tone_classes(@tone).figure]}>
            <.icon name={@icon} class="size-6" />
          </div>
          <div class="stat-title">{@title}</div>
          <div class={["stat-value", @emphasize && tone_classes(@tone).text]}>{@value}</div>
          <div class="stat-desc min-h-4">{@desc}</div>
        </div>
      </div>
    </.link>
    """
  end

  # The band, icon, and value classes for each tone, written out in full so
  # Tailwind generates them.
  defp tone_classes(:primary),
    do: %{band: "border-t-primary", figure: "bg-primary/15 text-primary", text: "text-primary"}

  defp tone_classes(:success),
    do: %{band: "border-t-success", figure: "bg-success/15 text-success", text: "text-success"}

  defp tone_classes(:warning),
    do: %{band: "border-t-warning", figure: "bg-warning/15 text-warning", text: "text-warning"}

  defp tone_classes(:error), do: %{band: "border-t-error", figure: "bg-error/15 text-error", text: "text-error"}
end
