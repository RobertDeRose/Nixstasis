import { Terminal } from "../../vendor/xterm"
import { FitAddon } from "../../vendor/xterm-addon-fit"

export default {
  mounted() {
    this.initTerminal()
  },
  updated() {
    if (this.el.dataset.token && this.el.dataset.token !== this.currentToken) {
      this.resetTerminal()
      this.initTerminal()
      return
    }

    if (this.term && this.el.dataset.active === "true") {
      requestAnimationFrame(() => this.fitAndReportSize())
    }

    if (this.el.dataset.closed === "true" && this.term && !this.closedMessageWritten) {
        this.term.write("\r\nTerminal session ended. Start a new session to reconnect.\r\n")
        this.closedMessageWritten = true
    }
  },
  destroyed() {
    this.clearAuthorizationRetry()
    this.clearJoinTimeout()

    if (this._resizeHandler) {
      window.removeEventListener('resize', this._resizeHandler)
    }
    this.notifyClosed()
    if (this.channel) {
      this.channel.leave()
    }
    if (this.term) {
      this.term.dispose()
    }
  },
  initTerminal() {
    this.currentToken = this.el.dataset.token || null
    this.terminalClosedNotified = false
    this.closedMessageWritten = false

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

    // Handle resizing
    this._resizeHandler = () => this.scheduleFit()
    window.addEventListener('resize', this._resizeHandler)

    this.resizeObserver = new ResizeObserver(() => this.scheduleFit())
    this.resizeObserver.observe(this.el)

    const socketToken = this.el.dataset.socketToken

    if (this.el.dataset.closed === "true") {
        this.term.write("Terminal session ended. Start a new session to reconnect.\r\n")
        this.closedMessageWritten = true
        return
    }

    if (window.connectTerminalSocket && socketToken) {
        this.socket = window.connectTerminalSocket(socketToken)
        this.fitBeforeJoin()
    } else {
        console.error("UserSocket not available for Terminal")
        this.term.write("Error: Connection unavailable.\r\n")
    }
  },

  resetTerminal() {
    this.clearAuthorizationRetry()
    this.clearJoinTimeout()

    if (this.channel) {
      const channel = this.channel
      this.channel = null
      this.hasConnected = false
      this.terminalClosedNotified = true
      channel.leave()
    }

    if (this.term) {
      this.term.dispose()
      this.term = null
    }

    this.waitingForAuthorization = false
    this.terminalClosedNotified = false
    this.closedMessageWritten = false
  },

  joinChannel() {
    this.clearAuthorizationRetry()

    const deviceId = this.el.dataset.deviceId
    const token = this.el.dataset.token
    const commandId = this.el.dataset.commandId

    if (!deviceId) {
        this.term.write("Error: No device ID provided.\r\n")
        return
    }

    if (!token) {
        this.term.write("Error: No access token provided.\r\n")
        return
    }

    if (commandId) {
      this.term.write("Waiting for device authorization...\r\n")
      this.waitingForAuthorization = true
    }

    const terminalSize = this.fitTerminal()
    this.lastReportedSize = terminalSize
    this.channel = this.socket.channel(`terminal:${deviceId}`, {
      token: token,
      command_id: commandId,
      columns: terminalSize.columns,
      rows: terminalSize.rows
    })
    this.channel.join()
      .receive("ok", resp => {
        this.hasConnected = true
        this.clearJoinTimeout()
        this.scheduleFit()
        this.reportSize()
        this.term.focus()
        if (commandId) this.pushEvent("terminal_authorized", {command_id: commandId})
      })
      .receive("error", resp => {
        this.clearJoinTimeout()
        console.error("Join error", resp)
        if (resp.code === "ssh_authorization_pending") {
          if (!this.waitingForAuthorization) {
            this.term.write("Waiting for device authorization...\r\n")
            this.waitingForAuthorization = true
          }
          this.scheduleAuthorizationRetry()
          return
        }
        this.term.write(`Unable to join terminal session: ${resp.reason || 'Unknown error'}.\r\n`)
      })
      .receive("timeout", () => {
        this.clearJoinTimeout()
        this.term.write("Unable to join terminal session: SSH connection timed out. Start a new session to retry.\r\n")
      })

    this.joinTimeoutTimer = window.setTimeout(() => {
      if (!this.hasConnected) {
        this.term.write("Still connecting to SSH tunnel...\r\n")
      }
    }, 8000)

    // Server -> Client
    this.channel.on("output", payload => {
        // payload should contain data (base64 or string)
        this.term.write(payload.data)
    })

    // Server -> Client (Session Warning)
    this.channel.on("session_warning", payload => {
        this.showWarning(payload.message)
    })

    this.channel.onClose(() => this.notifyClosed())

    // Client -> Server
    this.term.onData(data => {
        this.clearWarning()
        this.channel.push("input", {data: data})
    })
  },

  fitAndReportSize() {
    if (!this.term || !this.fitAddon) return

    this.fitTerminal()
    this.reportSize()

    this.term.scrollToBottom()
  },

  fitTerminal() {
    if (!this.term || !this.fitAddon || this.el.offsetWidth <= 0 || this.el.offsetHeight <= 0) {
      return {columns: this.term?.cols || 80, rows: this.term?.rows || 24}
    }

    this.fitAddon.fit()
    return {columns: this.term.cols, rows: this.term.rows}
  },

  fitBeforeJoin(attempt = 0) {
    requestAnimationFrame(() => {
      const size = this.fitTerminal()

      if ((this.el.offsetWidth <= 0 || this.el.offsetHeight <= 0) && attempt < 5) {
        this.fitBeforeJoin(attempt + 1)
        return
      }

      requestAnimationFrame(() => {
        this.fitTerminal()
        this.joinChannel()
      })
    })
  },

  reportSize() {
    if (!this.channel || this.channel.state !== "joined" || !this.term) return

    const columns = this.term.cols
    const rows = this.term.rows

    if (this.lastReportedSize?.columns === columns && this.lastReportedSize?.rows === rows) return

    this.lastReportedSize = {columns, rows}
    this.channel.push("resize", {columns, rows})
  },

  scheduleFit() {
    if (this.fitFrame) cancelAnimationFrame(this.fitFrame)

    this.fitFrame = requestAnimationFrame(() => {
      this.fitAndReportSize()
      requestAnimationFrame(() => this.fitAndReportSize())
    })
  },

  scheduleAuthorizationRetry() {
    this.clearAuthorizationRetry()
    this.authorizationRetryTimer = window.setTimeout(() => {
      if (this.channel) {
        const channel = this.channel
        this.channel = null
        channel.leave()
      }

      if (this.el.dataset.token === this.currentToken && this.el.dataset.closed !== "true") {
        this.joinChannel()
      }
    }, 1000)
  },

  clearAuthorizationRetry() {
    if (this.authorizationRetryTimer) {
      window.clearTimeout(this.authorizationRetryTimer)
      this.authorizationRetryTimer = null
    }
  },

  clearJoinTimeout() {
    if (this.joinTimeoutTimer) {
      window.clearTimeout(this.joinTimeoutTimer)
      this.joinTimeoutTimer = null
    }
  },

  notifyClosed() {
    if (this.terminalClosedNotified) return
    this.terminalClosedNotified = true
    const token = this.el.dataset.token
    const connected = this.channel?.state === "joined" || this.hasConnected
    if (token && connected) this.pushEvent("terminal_closed", {token: token})
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
