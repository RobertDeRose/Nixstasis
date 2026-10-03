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

    const socketToken = this.el.dataset.socketToken || null
    if (window.connectTerminalSocket && socketToken && socketToken !== this.currentSocketToken && this.el.dataset.closed !== "true" && !this.channel && !this.hasConnected) {
      this._terminalGeneration += 1
      this.clearJoinTimeout()
      this.currentSocketToken = socketToken
      this.socket = window.connectTerminalSocket(socketToken)
      this.fitBeforeJoin(0, this._terminalGeneration)
      return
    }

    if (this.term && this.el.dataset.active === "true") {
      this.scheduleFit()
    }

    if (this.el.dataset.closed === "true" && this.term && !this.closedMessageWritten) {
        this.term.write("\r\nTerminal session ended. Start a new session to reconnect.\r\n")
        this.closedMessageWritten = true
    }
  },
  destroyed() {
    this._destroyed = true
    this.disposeTerminalResources(true)
  },
  initTerminal() {
    this._destroyed = false
    this._terminalGeneration = (this._terminalGeneration || 0) + 1
    this.currentToken = this.el.dataset.token || null
    this.currentSocketToken = this.el.dataset.socketToken || null
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
    } else if (this.el.dataset.commandId) {
        this.term.write("Waiting for device authorization...\r\n")
    } else {
        console.error("UserSocket not available for Terminal")
        this.term.write("Error: Connection unavailable.\r\n")
    }
  },

  resetTerminal() {
    this.disposeTerminalResources(false)
    this.closedMessageWritten = false
  },

  disposeTerminalResources(notify = false) {
    this._terminalGeneration = (this._terminalGeneration || 0) + 1
    this.clearJoinTimeout()

    if (this.fitFrame) {
      cancelAnimationFrame(this.fitFrame)
      this.fitFrame = null
    }

    if (this._resizeHandler) {
      window.removeEventListener('resize', this._resizeHandler)
      this._resizeHandler = null
    }

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }

    if (notify) this.notifyClosed(true)

    if (this.channel) {
      const channel = this.channel
      this.channel = null
      channel.leave()
    }

    this.socket = null
    this.hasConnected = false

    if (this.term) {
      this.term.dispose()
      this.term = null
    }

    this.fitAddon = null
    this.clearWarning()
    this.terminalClosedNotified = false
  },

  joinChannel() {
    const generation = this._terminalGeneration
    if (!this.isGenerationActive(generation) || !this.socket || !this.term) return

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

    if (!commandId) {
        this.term.write("Error: No authorization command provided.\r\n")
        return
    }

    this.term.write("Waiting for device authorization...\r\n")

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
        if (!this.isGenerationActive(generation)) return
        this.hasConnected = true
        this.clearJoinTimeout()
        this.scheduleFit()
        this.reportSize()
        this.term.focus()
        if (commandId) this.pushEvent("terminal_authorized", {command_id: commandId})
      })
      .receive("error", resp => {
        if (!this.isGenerationActive(generation)) return
        this.clearJoinTimeout()
        console.error("Join error", resp)
        if (resp.code === "ssh_authorization_pending" || resp.code === "ssh_authorization_timeout") {
          this.term.write(`Unable to join terminal session: ${resp.reason || 'Authorization timed out'}. Start a new session to retry.\r\n`)
          this.notifyClosed(true)
          return
        }
        this.term.write(`Unable to join terminal session: ${resp.reason || 'Unknown error'}.\r\n`)
        this.notifyClosed(true)
      })
      .receive("timeout", () => {
        if (!this.isGenerationActive(generation)) return
        this.clearJoinTimeout()
        this.term.write("Unable to join terminal session: SSH connection timed out. Start a new session to retry.\r\n")
        this.notifyClosed(true)
      })

    const joinGeneration = generation
    this.joinTimeoutTimer = window.setTimeout(() => {
      this.joinTimeoutTimer = null

      if (this.isGenerationActive(joinGeneration) && !this.hasConnected && this.term) {
        this.term.write("Still connecting to SSH tunnel...\r\n")
      }
    }, 8000)

    // Server -> Client
    this.channel.on("output", payload => {
        // payload should contain data (base64 or string)
        if (this.isGenerationActive(generation) && this.term) this.term.write(payload.data)
    })

    // Server -> Client (Session Warning)
    this.channel.on("session_warning", payload => {
        if (this.isGenerationActive(generation)) this.showWarning(payload.message)
    })

    this.channel.onClose(() => {
      if (this.isGenerationActive(generation)) this.notifyClosed()
    })

    // Client -> Server
    this.term.onData(data => {
        if (!this.isGenerationActive(generation) || !this.channel) return
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

  fitBeforeJoin(attempt = 0, generation = this._terminalGeneration) {
    requestAnimationFrame(() => {
      if (!this.isGenerationActive(generation)) return

      this.fitTerminal()

      if ((this.el.offsetWidth <= 0 || this.el.offsetHeight <= 0) && attempt < 5) {
        this.fitBeforeJoin(attempt + 1, generation)
        return
      }

      requestAnimationFrame(() => {
        if (!this.isGenerationActive(generation)) return
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

    const generation = this._terminalGeneration
    this.fitFrame = requestAnimationFrame(() => {
      this.fitFrame = null
      if (!this.isGenerationActive(generation)) return

      this.fitAndReportSize()
      requestAnimationFrame(() => {
        if (this.isGenerationActive(generation)) this.fitAndReportSize()
      })
    })
  },

  isGenerationActive(generation) {
    return !this._destroyed && generation === this._terminalGeneration
  },

  clearJoinTimeout() {
    if (this.joinTimeoutTimer) {
      window.clearTimeout(this.joinTimeoutTimer)
      this.joinTimeoutTimer = null
    }
  },

  notifyClosed(force = false) {
    if (this.terminalClosedNotified) return
    this.terminalClosedNotified = true
    const token = this.el.dataset.token
    const connected = this.channel?.state === "joined" || this.hasConnected
    if (token && (connected || force)) this.pushEvent("terminal_closed", {token: token})
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
