// Arrow, Home, and End keys move between tabs and activate them, following the
// WAI-ARIA tabs pattern. The server renders tabindex so only the selected tab
// is a Tab stop.
const KEY_OFFSETS = {ArrowLeft: -1, ArrowRight: 1}

export default {
  // Listens on the tablist so one handler serves every tab.
  mounted() {
    // Moves to the previous, next, first, or last enabled tab and clicks it so
    // the server selects it. Other keys, and any key with Alt, Ctrl, or Meta,
    // keep their browser behaviour.
    this.handleKeydown = (event) => {
      const tabs = Array.from(this.el.querySelectorAll("[role='tab']:not([disabled])"))
      const current = tabs.indexOf(event.target)
      if (current === -1) return

      // Modified arrows are browser shortcuts such as Alt+Left for back.
      if (event.altKey || event.ctrlKey || event.metaKey) return

      let next
      if (event.key in KEY_OFFSETS) {
        next = (current + KEY_OFFSETS[event.key] + tabs.length) % tabs.length
      } else if (event.key === "Home") {
        next = 0
      } else if (event.key === "End") {
        next = tabs.length - 1
      } else {
        return
      }

      event.preventDefault()
      tabs[next].focus()
      tabs[next].click()
    }

    this.el.addEventListener("keydown", this.handleKeydown)
  },

  // Removes the keydown listener added in mounted().
  destroyed() {
    this.el.removeEventListener("keydown", this.handleKeydown)
  }
}
