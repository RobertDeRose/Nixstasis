export default {
  mounted() {
    this.updateState()
  },
  updated() {
    this.updateState()
  },
  updateState() {
    const selectedCount = parseInt(this.el.dataset.selectedCount) || 0
    const totalCount = parseInt(this.el.dataset.totalCount) || 0

    // Logic:
    // 0 selected -> unchecked, indeterminate=false
    // all selected -> checked, indeterminate=false
    // some selected -> unchecked (visually handled by indeterminate), indeterminate=true

    if (selectedCount === 0) {
      this.el.checked = false
      this.el.indeterminate = false
    } else if (selectedCount === totalCount && totalCount > 0) {
      this.el.checked = true
      this.el.indeterminate = false
    } else {
      this.el.checked = false // Checkbox standard behavior: indeterminate overrides checked visually
      this.el.indeterminate = true
    }
  }
}
