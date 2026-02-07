import ApexCharts from "../../vendor/apexcharts"

export default {
  mounted() {
    this.initChart()
  },
  updated() {
    // Optional: Check if specific data attributes changed to update without re-rendering everything
    // For now, we rely on the LiveView to drive updates or events
  },
  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  },
  initChart() {
    if (!this.el.id) {
      console.error("ApexChart hook requires a unique ID on the element")
      return
    }

    try {
      const options = JSON.parse(this.el.dataset.options || "{}")
      const series = JSON.parse(this.el.dataset.series || "[]")

      // Merge series into options if not already present or if separate
      options.series = series

      this.chart = new ApexCharts(this.el, options)
      this.chart.render()
    } catch (e) {
      console.error("Error initializing ApexChart:", e)
    }
  }
}
