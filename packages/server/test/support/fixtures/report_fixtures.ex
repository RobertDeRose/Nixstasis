defmodule Nixstasis.TestSupport.ReportFixtures do
  @moduledoc false

  def sample_rows do
    [
      %{"name" => "Alpha", "source" => "telemetry", "column_count" => 2, "temp" => 20},
      %{"name" => "Bravo", "source" => "telemetry", "column_count" => 3, "temp" => 30},
      %{"name" => "Charlie", "source" => "e2e", "column_count" => 1, "temp" => 10}
    ]
  end
end
