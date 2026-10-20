// Returns focus to the element that opened a modal once the modal is removed:
// the data-focus-return-target element when given, otherwise whatever had focus
// when the modal mounted.
export default {
  // The modal mounts while its opener still has focus.
  mounted() {
    this.opener = document.activeElement
  },

  // Skips an opener that is gone, such as the row of a deleted item.
  destroyed() {
    const target = document.getElementById(this.el.dataset.focusReturnTarget) || this.opener
    if (target?.isConnected) target.focus()
  }
}
