defmodule Nixstasis.TestSupport.WebhookCapturePlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    test_pid = Keyword.fetch!(opts, :test_pid)
    {:ok, body, conn} = read_body(conn)

    send(test_pid, {:webhook_request, conn.method, conn.request_path, body})

    send_resp(conn, 200, "ok")
  end
end
