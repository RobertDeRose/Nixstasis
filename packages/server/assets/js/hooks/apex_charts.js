import ApexCharts from "../../vendor/apexcharts"

const cssColor = (name, fallback) => {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  return value || fallback
}

const hexToRgba = (color, alpha) => {
  if (!color.startsWith("#") || ![4, 7].includes(color.length)) {
    return color
  }

  const hex = color.length === 4
    ? color.replace(/^#(.)(.)(.)$/, "#$1$1$2$2$3$3")
    : color
  const number = Number.parseInt(hex.slice(1), 16)
  const red = (number >> 16) & 255
  const green = (number >> 8) & 255
  const blue = number & 255

  return `rgba(${red}, ${green}, ${blue}, ${alpha})`
}

const currentTheme = () => {
  if (document.documentElement.dataset.theme) {
    return document.documentElement.dataset.theme
  }

  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

const themedOptions = (options) => {
  const baseContent = cssColor("--color-base-content", "#2c3947")
  const base200 = cssColor("--color-base-200", "#ebeded")
  const base300 = cssColor("--color-base-300", "#d4d6d8")
  const mutedContent = hexToRgba(baseContent, 0.72)
  const faintContent = hexToRgba(baseContent, 0.18)

  const themed = {
    ...options,
    chart: {
      ...(options.chart || {}),
      foreColor: mutedContent
    },
    grid: {
      borderColor: faintContent,
      ...(options.grid || {})
    },
    legend: {
      ...(options.legend || {}),
      labels: {
        colors: mutedContent,
        ...((options.legend || {}).labels || {})
      }
    },
    title: {
      ...(options.title || {}),
      style: {
        color: baseContent,
        fontWeight: 700,
        ...((options.title || {}).style || {})
      }
    },
    tooltip: {
      theme: currentTheme(),
      ...(options.tooltip || {})
    },
    xaxis: {
      ...(options.xaxis || {}),
      labels: {
        ...((options.xaxis || {}).labels || {}),
        style: {
          colors: mutedContent,
          ...(((options.xaxis || {}).labels || {}).style || {})
        }
      },
      axisBorder: {
        color: faintContent,
        ...((options.xaxis || {}).axisBorder || {})
      },
      axisTicks: {
        color: faintContent,
        ...((options.xaxis || {}).axisTicks || {})
      }
    },
    yaxis: {
      ...(options.yaxis || {}),
      labels: {
        ...((options.yaxis || {}).labels || {}),
        style: {
          colors: mutedContent,
          ...(((options.yaxis || {}).labels || {}).style || {})
        }
      }
    }
  }

  if (options.chart?.type === "radialBar") {
    themed.plotOptions = {
      ...(options.plotOptions || {}),
      radialBar: {
        ...((options.plotOptions || {}).radialBar || {}),
        track: {
          ...(((options.plotOptions || {}).radialBar || {}).track || {}),
          background: base200,
          dropShadow: {
            ...((((options.plotOptions || {}).radialBar || {}).track || {}).dropShadow || {}),
            enabled: true,
            top: 2,
            left: 0,
            color: base300,
            opacity: 0.6,
            blur: 2
          }
        },
        dataLabels: {
          ...(((options.plotOptions || {}).radialBar || {}).dataLabels || {}),
          name: {
            color: mutedContent,
            ...(((((options.plotOptions || {}).radialBar || {}).dataLabels || {}).name) || {})
          },
          value: {
            color: baseContent,
            ...(((((options.plotOptions || {}).radialBar || {}).dataLabels || {}).value) || {})
          }
        }
      }
    }
  }

  return themed
}

const splitOptionsAndSeries = (element) => {
  const options = JSON.parse(element.dataset.options || "{}")

  if (element.dataset.series) {
    options.series = JSON.parse(element.dataset.series)
  }

  const series = options.series
  delete options.series

  return { options: themedOptions(options), series }
}

export default {
  mounted() {
    this.initChart()
  },
  destroyed() {
    if (this.themeObserver) {
      this.themeObserver.disconnect()
    }

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
      const { options, series } = splitOptionsAndSeries(this.el)

      if (series) {
        options.series = series
      }

      this.chart = new ApexCharts(this.el, options)
      this.chart.render()
      this.observeTheme()
    } catch (e) {
      console.error("Error initializing ApexChart:", e)
    }
  },
  updated() {
    if (!this.chart) {
      this.initChart()
      return
    }

    try {
      const { options, series } = splitOptionsAndSeries(this.el)

      this.chart.updateOptions(options, false, false)

      if (series) {
        this.chart.updateSeries(series, false)
      }

      if (this.el.dataset.active === "true") {
        requestAnimationFrame(() => this.chart.updateOptions(options, false, false))
      }
    } catch (e) {
      console.error("Error updating ApexChart:", e)
    }
  },
  observeTheme() {
    if (this.themeObserver) {
      return
    }

    this.themeObserver = new MutationObserver(() => this.updated())
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"]
    })
  }
}
