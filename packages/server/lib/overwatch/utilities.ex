defmodule Nixstasis.Utilities do
  @moduledoc """
  Common utility functions
  """

  @doc """
  Formats a MAC address to the standard colon-separated format.

  ## Examples
      iex> Nixstasis.Utilities.format_mac_address("aabbccddeeff")
      "AA:BB:CC:DD:EE:FF"

      iex> Nixstasis.Utilities.format_mac_address("aa-bb-cc-dd-ee-ff")
      "AA:BB:CC:DD:EE:FF"

      iex> Nixstasis.Utilities.format_mac_address("AA:BB:CC:DD:EE:FF")
      "AA:BB:CC:DD:EE:FF"

      iex> Nixstasis.Utilities.format_mac_address("  12::aB:Cd:EF:34:56 -")
      "12:AB:CD:EF:34:56"
  """
  def format_mac_address(raw_mac) do
    # 1. Clean the string
    clean = String.replace(raw_mac, ~r/[^a-fA-F0-9]/, "") |> String.upcase()

    # 2. Use binary matching to format if the length is correct (12 chars)
    # format: off
    case clean do
      <<a::2-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::2-bytes, f::2-bytes>> -> "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}"
      _ -> clean
    end

    # format: on
  end
end
