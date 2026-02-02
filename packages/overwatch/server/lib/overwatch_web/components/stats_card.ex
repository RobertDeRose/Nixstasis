defmodule NixstasisWeb.Components.StatsCard do
  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:value, :string, required: true)
  attr(:desc, :string, default: nil)
  attr(:color_class, :string, default: "")

  def stats_card(assigns) do
    ~H"""
    <div class="stats shadow bg-base-100">
      <div class="stat place-items-center">
        <div class="stat-title">{@title}</div>
        <div class={"stat-value " <> @color_class}>{@value}</div>
        <div :if={@desc} class="stat-desc">{@desc}</div>
      </div>
    </div>
    """
  end
end
