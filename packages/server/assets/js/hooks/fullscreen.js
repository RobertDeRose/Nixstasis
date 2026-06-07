export default {
  mounted() {
    this.maximizeBtn = document.getElementById("tab-maximize-button")
    this.fullscreenIcon = this.el.querySelector('[class*="fa-"]')

    this.handleClick = (event) => {
      const target = this.targetElement()
      if (!target) return

      if (document.fullscreenElement) {
        document.exitFullscreen().catch(() => {})
      } else {
        target.requestFullscreen().catch(() => {})
      }
    }

    this.handleFullscreenChange = () => this.updateUI()

    this.el.addEventListener("click", this.handleClick)
    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    this.updateUI()
  },

  updated() {
    this.maximizeBtn = document.getElementById("tab-maximize-button")
    this.fullscreenIcon = this.el.querySelector('[class*="fa-"]')
    this.updateUI()
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    document.removeEventListener("fullscreenchange", this.handleFullscreenChange)
  },

  targetElement() {
    const targetId = this.el.dataset.fullscreenTarget
    if (!targetId) return null
    return document.getElementById(targetId)
  },

  updateUI() {
    const isFullscreen = !!document.fullscreenElement
    const wrapper = this.el.parentElement

    if (wrapper?.dataset) {
      wrapper.dataset.tip = isFullscreen ? "Exit Fullscreen" : "Fullscreen"
    }

    if (this.maximizeBtn) {
      this.maximizeBtn.classList.toggle("hidden", isFullscreen)
    }

    if (this.fullscreenIcon) {
      this.fullscreenIcon.classList.toggle("fa-maximize", !isFullscreen)
      this.fullscreenIcon.classList.toggle("fa-minimize", isFullscreen)
    }
  }
}
