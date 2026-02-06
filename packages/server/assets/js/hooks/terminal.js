import { Terminal } from "../../vendor/xterm"
import { FitAddon } from "../../vendor/xterm-addon-fit"

export default {
  mounted() {
    this.initTerminal()
  },
  destroyed() {
    if (this.term) {
      this.term.dispose()
    }
    if (this.channel) {
      this.channel.leave()
    }
  },
  initTerminal() {
    // Initialize xterm.js
    this.term = new Terminal({
      cursorBlink: true,
      theme: {
        background: '#1e1e1e',
        foreground: '#ffffff'
      }
    })

    this.fitAddon = new FitAddon()
    this.term.loadAddon(this.fitAddon)

    // Clear the container first
    this.el.innerHTML = ""
    this.term.open(this.el)
    this.fitAddon.fit()

    // Handle resizing
    window.addEventListener('resize', () => this.fitAddon.fit())

    // Connect to Phoenix Channel
    // We assume `window.liveSocket` has the socket available, but we usually need a separate socket for Channels
    // or we can reuse the one if exposed. `app.js` doesn't explicitly expose `socket` instance globally cleanly
    // except via liveSocket. However, for a simple terminal, we might want a dedicated channel on the socket.

    // Let's assume we can get the socket from liveSocket or create a new one.
    // Standard pattern: import socket from "../user_socket.js" if enabled.
    // Since we don't have user_socket.js enabled in app.js (commented out), we need to check if we can reuse liveSocket's connection
    // or just enable user_socket.

    // For now, let's try to grab the socket from the liveSocket if possible, or just create a new one.
    // Actually, `app.js` imports `Socket`.

    // Let's use the `user_socket.js` pattern as it is cleaner for channels.
    // But since I cannot easily modify multiple files to enable user_socket without checking,
    // I will try to use `window.liveSocket.socket` if available, or just instantiate one here
    // (though slightly inefficient to have 2 connections).

    // Better approach: We will enable user_socket in the next step.
    // For this hook, let's assume `window.userSocket` is available or we import it.
    // Since imports are static, I'll rely on `window.userSocket` which I will set up in app.js.

    if (window.userSocket) {
        this.joinChannel(window.userSocket)
    } else {
        console.error("UserSocket not available for Terminal")
        this.term.write("Error: Connection unavailable.\r\n")
    }
  },

  joinChannel(socket) {
    const deviceId = this.el.dataset.deviceId
    const token = this.el.dataset.token

    if (!deviceId) {
        this.term.write("Error: No device ID provided.\r\n")
        return
    }

    if (!token) {
        this.term.write("Error: No access token provided.\r\n")
        return
    }

    this.channel = socket.channel(`terminal:${deviceId}`, {token: token})

    this.channel.join()
      .receive("ok", resp => {
        this.term.write("Connected to terminal session.\r\n")
        this.term.focus()
      })
      .receive("error", resp => {
        console.error("Join error", resp)
        this.term.write(`Unable to join terminal session: ${resp.reason || 'Unknown error'}.\r\n`)
      })

    // Server -> Client
    this.channel.on("output", payload => {
        // payload should contain data (base64 or string)
        this.term.write(payload.data)
    })

    // Server -> Client (Session Warning)
    this.channel.on("session_warning", payload => {
        this.showWarning(payload.message)
    })

    // Client -> Server
    this.term.onData(data => {
        this.clearWarning()
        this.channel.push("input", {data: data})
    })
  },

  showWarning(message) {
    if (this.warningEl) return

    this.warningEl = document.createElement("div")
    this.warningEl.className = "absolute top-2 right-2 bg-warning text-warning-content px-4 py-2 rounded shadow-lg z-10 transition-opacity duration-300"
    this.warningEl.innerText = message
    this.el.appendChild(this.warningEl)
  },

  clearWarning() {
    if (this.warningEl) {
      this.warningEl.remove()
      this.warningEl = null
    }
  }
}
