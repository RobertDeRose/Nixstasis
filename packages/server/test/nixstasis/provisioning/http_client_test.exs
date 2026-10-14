defmodule Nixstasis.Provisioning.HTTPClientTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Provisioning.HTTPClient

  @small_limit 64

  test "submit aborts an oversized accepted response before JSON decoding" do
    body = Jason.encode!(%{"job_id" => "job-1", "padding" => String.duplicate("x", 256)})

    assert {:error, {:response_too_large, 202, @small_limit}} =
             HTTPClient.submit("http://atom.test/api/config", "config", "config.toml",
               max_response_bytes: @small_limit,
               plug: response_plug(202, body)
             )
  end

  test "submit applies the receive budget to error responses" do
    body = Jason.encode!(%{"error" => String.duplicate("x", 256)})

    assert {:error, {:response_too_large, 500, @small_limit}} =
             HTTPClient.submit("http://atom.test/api/config", "config", "config.toml",
               max_response_bytes: @small_limit,
               plug: response_plug(500, body)
             )
  end

  test "get_job aborts an oversized polling response before JSON decoding" do
    body = Jason.encode!(%{"id" => "job-1", "state" => "running", "padding" => String.duplicate("x", 256)})

    assert {:error, {:response_too_large, 200, @small_limit}} =
             HTTPClient.get_job("http://atom.test/api/jobs/job-1",
               max_response_bytes: @small_limit,
               plug: response_plug(200, body)
             )
  end

  test "bounded responses are assembled and decoded normally" do
    body = Jason.encode!(%{"job_id" => "job-1", "job_url" => "/api/jobs/job-1", "state" => "submitted"})

    assert {:ok, %{"job_id" => "job-1", "state" => "submitted"}} =
             HTTPClient.submit("http://atom.test/api/config", "config", "config.toml",
               max_response_bytes: 256,
               plug: response_plug(202, body)
             )
  end

  test "the streaming collector halts without retaining the chunk that crosses the limit" do
    into = HTTPClient.bounded_response_into(8)
    request = Req.new()
    response = Req.Response.new()

    assert {:cont, {^request, response}} = into.({:data, "1234"}, {request, response})
    assert {:bounded_response, 4, ["1234"]} = response.body

    assert {:halt, {^request, response}} = into.({:data, "56789"}, {request, response})
    assert response.body == {:response_too_large, 8}
  end

  defp response_plug(status, body) do
    fn conn -> Plug.Conn.send_resp(conn, status, body) end
  end
end
