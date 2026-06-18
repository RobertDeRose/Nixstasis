// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// Bring in the Socket package that we'll use to connect
// with the main application connection details.
import {Socket} from "phoenix"

// And connect to the path in "lib/nixstasis_web/endpoint.ex". We pass the
// token for authentication. Read below how it should be used.
let socket = null
let activeToken = null

// When you connect, you'll often need to authenticate the client.
// For example, imagine you have an authentication plug, `MyAuth`,
// which authenticates the session and assigns a `:current_user`.
// If the current user exists you can assign the user's token in
// the connection for use in the layout.
//
// In your "lib/nixstasis_web/router.ex":
//
//     pipeline :browser do
//       ...
//       plug MyAuth
//       plug :put_user_token
//     end
//
//     defp put_user_token(conn, _) do
//       if current_user = conn.assigns[:current_user] do
//         token = Phoenix.Token.sign(conn, "user socket", current_user.id)
//         assign(conn, :user_token, token)
//       else
//         conn
//       end
//     end
//
// Now you need to pass this token to JavaScript. You can do so
// inside "lib/nixstasis_web/templates/layout/app.html.heex":
//
//     <script>window.userToken = "<%= assigns[:user_token] %>";</script>
//
// You will need to verify the user token in the "connect/3" function
// in "lib/nixstasis_web/channels/user_socket.ex":
//
//     def connect(%{"token" => token}, socket, _connect_info) do
//       # max_age: 1209600 is equivalent to two weeks in seconds
//       case Phoenix.Token.verify(socket, "user socket", token, max_age: 1_209_600) do
//         {:ok, user_id} ->
//           {:ok, assign(socket, :user, user_id)}
//         {:error, reason} ->
//           :error
//       end
//     end
//
// Finally, connect to the socket:
window.connectTerminalSocket = (token) => {
  if (!socket || activeToken !== token) {
    if (socket) {
      socket.disconnect()
    }

    socket = new Socket("/socket", {
      params: {token: token},
      rejoinAfterMs: () => 1000,
    })
    socket.connect()
    activeToken = token
    window.userSocket = socket
  }

  return socket
}

// Export the socket to be used by hooks
window.userSocket = socket

export default socket
