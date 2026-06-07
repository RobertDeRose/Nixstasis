export default {
  mounted() {
    this.handleClick = (event) => {
      const target = this.targetElement()
      if (!target) return

      if (document.fullscreenElement) {
        document.exitFullscreen().catch(() => {})
      } else {
        target.requestFullscreen().catch(() => {})
      }
    }

    this.handleFullscreenChange = () => this.updateLabel()

    this.el.addEventListener("click", this.handleClick)
    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    this.updateLabel()
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

  updateLabel() {
    const isFullscreen = !!document.fullscreenElement
    const enter = this.el.querySelector(".fullscreen-icon-enter")
    const exit = this.el.querySelector(".fullscreen-icon-exit")
    if (enter) enter.classList.toggle("hidden", isFullscreen)
    if (exit) exit.classList.toggle("hidden", !isFullscreen)
    const wrapper = this.el.parentElement
    if (wrapper?.dataset) {
      wrapper.dataset.tip = isFullscreen ? "Exit Fullscreen" : "Fullscreen"
    }
  }
}
