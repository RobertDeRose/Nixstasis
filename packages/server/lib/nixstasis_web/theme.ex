defmodule NixstasisWeb.Theme do
  @moduledoc """
  Colour palettes and highlight colours an operator can choose.

  The browser stores both choices and sets `data-palette` and `data-highlight`
  on the root element. The default palette is the daisyUI theme in
  `assets/css/app.css`; every other palette replaces its tokens under
  `:root[data-palette="<value>"]` there. A highlight overrides the palette's
  primary and accent under `:root[data-highlight="<value>"]`; the default keeps
  the palette's own colour, and the High Contrast palette ignores highlights.
  """

  @default_palette "coherent-current"
  @palettes [
    {"Coherent Current", @default_palette},
    {"Glacier Console", "glacier-console"},
    {"Signal Slate", "signal-slate"},
    {"Deepwater Operations", "deepwater-operations"},
    {"Mineral Glass", "mineral-glass"},
    {"Northstar Amber", "northstar-amber"},
    {"Electric Fjord", "electric-fjord"},
    {"Quiet Instrument", "quiet-instrument"},
    {"Aurora Control", "aurora-control"},
    {"Maglev Neon", "maglev-neon"},
    {"High Contrast", "high-contrast"}
  ]

  @doc "Returns `{label, value}` pairs for every palette, default first."
  def palettes, do: @palettes

  @doc "Returns the value of every palette."
  def palette_values, do: Enum.map(@palettes, &elem(&1, 1))

  @doc "Returns the palette used when none is stored or the stored one is unknown."
  def default_palette, do: @default_palette

  @default_highlight "palette"
  @highlights [
    {"Palette default", @default_highlight},
    {"Teal", "teal"},
    {"Deep Blue", "deep-blue"},
    {"Cyan", "cyan"},
    {"Green", "green"},
    {"Amber", "amber"},
    {"Magenta", "magenta"}
  ]

  @doc "Returns `{label, value}` pairs for every highlight, default first."
  def highlights, do: @highlights

  @doc "Returns the value of every highlight."
  def highlight_values, do: Enum.map(@highlights, &elem(&1, 1))

  @doc "Returns the highlight used when none is stored or the stored one is unknown."
  def default_highlight, do: @default_highlight
end
