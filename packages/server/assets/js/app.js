// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/nixstasis"
import topbar from "../vendor/topbar"
import ApexChart from "./hooks/apex_charts"
import IndeterminateCheckbox from "./hooks/indeterminate_checkbox"
import TerminalHook from "./hooks/terminal"
import Fullscreen from "./hooks/fullscreen"
import CodeMirrorHook from "./hooks/code_mirror"

const SchemaFieldInput = {
  mounted() {
    this.onKeydown = (event) => {
      const fieldId = this.el.dataset.fieldId
      const fieldLevel = this.el.dataset.fieldLevel || "0"
      if (!fieldId) return

      if (event.key === "Enter") {
        event.preventDefault()
        event.stopPropagation()
        this.pushEvent("schema_field_name_keydown", {
          id: fieldId,
          key: "Enter",
          value: this.el.value,
          level: fieldLevel
        })
      } else if (event.key === "Backspace" && this.el.value === "") {
        event.preventDefault()
        event.stopPropagation()
        this.pushEvent("schema_field_name_keydown", {
          id: fieldId,
          key: "Backspace",
          value: "",
          level: fieldLevel
        })
      } else if (event.key === "Tab" && event.shiftKey) {
        event.preventDefault()
        event.stopPropagation()
        this.pushEvent("schema_field_name_keydown", {
          id: fieldId,
          key: "Tab",
          shift_key: true,
          value: this.el.value,
          level: fieldLevel
        })
      }
    }
    this.el.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }
  }
}

const SchemaFieldSelect = {
  mounted() {
    this.onKeydown = (event) => {
      const fieldId = this.el.dataset.fieldId
      const fieldLevel = this.el.dataset.fieldLevel || "0"
      if (!fieldId) return

      if (event.key === "Enter") {
        event.preventDefault()
        const row = this.el.closest(".schema-field-row")
        const nameValue = row?.querySelector("input[id^='sf-name-']")?.value || ""
        this.pushEvent("schema_field_type_keydown", {
          id: fieldId,
          key: "Enter",
          level: fieldLevel,
          value: this.el.value,
          name_value: nameValue
        })
      }
    }
    this.el.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }
  }
}

const ReportColumnTitle = {
  mounted() {
    this.onKeydown = event => {
      if (event.key === "Enter") {
        event.preventDefault()
      }
    }

    if (this.el.__reportColumnTitleOnKeydown) {
      this.el.removeEventListener("keydown", this.el.__reportColumnTitleOnKeydown)
    }

    this.el.addEventListener("keydown", this.onKeydown)
    this.el.__reportColumnTitleOnKeydown = this.onKeydown
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }

    if (this.el.__reportColumnTitleOnKeydown === this.onKeydown) {
      this.el.__reportColumnTitleOnKeydown = null
    }
  },
}

const ReportFilterValue = {
  mounted() {
    this.onKeydown = event => {
      if (event.key === "Enter") {
        event.preventDefault()
      }
    }

    this.el.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }
  },
}

const ReportNameAutofocus = {
  mounted() {
    const focusNameInput = () => {
      if (!this.el || !document.body.contains(this.el)) return
      this.el.focus()
      this.el.select()
    }

    requestAnimationFrame(focusNameInput)
    setTimeout(focusNameInput, 120)
  },
}

const ReportBuilderKeyboard = {
  mounted() {
    this.onKeydown = event => {
      if (event.defaultPrevented) return

      const key = event.key
      const isMac = /Mac|iPhone|iPad|iPod/.test(navigator.platform)

      if (key === "Escape") {
        event.preventDefault()
        const closeButton = document.querySelector("#report-modal button[aria-label='close']")
        closeButton?.click()
        return
      }

      if (key === "Enter") {
        const saveShortcutPressed = isMac ? event.metaKey : event.ctrlKey

        if (saveShortcutPressed) {
          const saveButton = document.getElementById("report-save-report")
          if (saveButton?.disabled) return

          event.preventDefault()
          if (typeof this.el.requestSubmit === "function") {
            this.el.requestSubmit()
          } else {
            saveButton?.click()
          }
          return
        }
      }

      if (key !== "Tab") return

      const tabOrder = this.getTabOrder()
      const activeId = document.activeElement?.id
      const index = tabOrder.indexOf(activeId)
      if (index === -1) return

      event.preventDefault()

      const delta = event.shiftKey ? -1 : 1
      const nextIndex = (index + delta + tabOrder.length) % tabOrder.length
      const nextId = tabOrder[nextIndex]
      document.getElementById(nextId)?.focus()
    }

    this.onFocusIn = event => {
      const saveButton = document.getElementById("report-save-report")
      if (!saveButton) return

      if (event.target?.id === "report-save-report" && !saveButton.disabled) {
        saveButton.classList.add("animate-pulse")
      }
    }

    this.onFocusOut = event => {
      if (event.target?.id === "report-save-report") {
        event.target.classList.remove("animate-pulse")
      }
    }

    if (this.el.__reportBuilderOnKeydown) {
      this.el.removeEventListener("keydown", this.el.__reportBuilderOnKeydown)
    }

    if (this.el.__reportBuilderOnFocusIn) {
      this.el.removeEventListener("focusin", this.el.__reportBuilderOnFocusIn)
    }

    if (this.el.__reportBuilderOnFocusOut) {
      this.el.removeEventListener("focusout", this.el.__reportBuilderOnFocusOut)
    }

    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("focusin", this.onFocusIn)
    this.el.addEventListener("focusout", this.onFocusOut)
    this.el.__reportBuilderOnKeydown = this.onKeydown
    this.el.__reportBuilderOnFocusIn = this.onFocusIn
    this.el.__reportBuilderOnFocusOut = this.onFocusOut
  },

  getTabOrder() {
    const ids = ["report-name-input", "report-schema-id", "report-add-column"]

    const columnRows = Array.from(this.el.querySelectorAll("[data-column-row-id]"))
    for (const row of columnRows) {
      const schemaField = row.querySelector("select[id^='report-field-path-']")
      const columnTitle = row.querySelector("input[id^='report-field-alias-']")
      if (schemaField?.id) ids.push(schemaField.id)
      if (columnTitle?.id) ids.push(columnTitle.id)
    }

    ids.push("report-add-filter")

    const filterRows = Array.from(this.el.querySelectorAll("[data-filter-row-id]"))
    for (const row of filterRows) {
      const filterField = row.querySelector("select[id^='report-filter-field-']")
      const filterOperator = row.querySelector("select[id^='report-filter-operator-']")
      const filterValue = row.querySelector("input[id^='report-filter-value-']")
      if (filterField?.id) ids.push(filterField.id)
      if (filterOperator?.id) ids.push(filterOperator.id)
      if (filterValue?.id) ids.push(filterValue.id)
    }

    ids.push("report-save-report")

    return ids.filter((id, index) => {
      if (!id || ids.indexOf(id) !== index) return false
      const el = document.getElementById(id)
      return !!el && !el.disabled
    })
  },

  destroyed() {
    if (this.onKeydown) {
      this.el.removeEventListener("keydown", this.onKeydown)
    }

    if (this.onFocusIn) {
      this.el.removeEventListener("focusin", this.onFocusIn)
    }

    if (this.onFocusOut) {
      this.el.removeEventListener("focusout", this.onFocusOut)
    }

    if (this.el.__reportBuilderOnKeydown === this.onKeydown) {
      this.el.__reportBuilderOnKeydown = null
    }

    if (this.el.__reportBuilderOnFocusIn === this.onFocusIn) {
      this.el.__reportBuilderOnFocusIn = null
    }

    if (this.el.__reportBuilderOnFocusOut === this.onFocusOut) {
      this.el.__reportBuilderOnFocusOut = null
    }
  },
}

const AlertRuleBuilderKeyboard = {
  mounted() {
    this.modalRoot = document.getElementById("rule-modal")
    this.lastActiveModalId = null
    this.previousActiveElement = null
    this.lastFocusedElement = null

    this.isVisible = element => {
      if (!element || !document.body.contains(element)) return false

      const style = window.getComputedStyle(element)
      return style.display !== "none" && style.visibility !== "hidden"
    }

    this.getVisibleModalRoots = () => {
      const roots = Array.from(document.querySelectorAll("[role='dialog'][aria-modal='true']"))
        .map(dialog => dialog.closest("[id]"))
        .filter(root => root && this.isVisible(root))

      return roots.filter((root, index) => roots.indexOf(root) === index)
    }

    this.getActiveModal = () => {
      const visibleModals = this.getVisibleModalRoots()
      return visibleModals[visibleModals.length - 1] || null
    }

    this.getFocusableElements = modalRoot => {
      if (!modalRoot) return []

      const selector = [
        "button",
        "input",
        "select",
        "textarea",
        "a[href]",
        "[tabindex]:not([tabindex='-1'])",
      ].join(",")

      return Array.from(modalRoot.querySelectorAll(selector)).filter(el => {
        if (el.matches("[role='dialog'], input[type='hidden']")) return false
        if (el.disabled || el.getAttribute("aria-hidden") === "true") return false
        return this.isVisible(el)
      })
    }

    this.focusActiveModal = modalRoot => {
      const targetId =
        modalRoot.dataset.focusTarget ||
        modalRoot.querySelector("[data-initial-focus-id]")?.dataset.initialFocusId
      const focusables = this.getFocusableElements(modalRoot)
      const target = targetId ? document.getElementById(targetId) : null
      const focusTarget = target && focusables.includes(target) ? target : focusables[0]

      focusTarget?.focus()
    }

    this.onFocusIn = event => {
      const target = event.target
      if (!this.modalRoot?.contains(target) || target.closest?.("button[aria-label='close']")) return

      if (this.getFocusableElements(this.modalRoot).includes(target)) {
        this.lastFocusedElement = target
      }
    }

    this.scheduleActiveModalFocus = () => {
      const activeModal = this.getActiveModal()

      if (!activeModal) {
        this.lastActiveModalId = null
        return
      }

      if (activeModal.id === this.lastActiveModalId) return

      if (activeModal.id !== this.modalRoot?.id) {
        const lastFocusedElement = this.lastFocusedElement
        this.previousActiveElement =
          lastFocusedElement &&
          lastFocusedElement.isConnected &&
          this.modalRoot?.contains(lastFocusedElement)
            ? lastFocusedElement
            : document.activeElement
      }

      const activeModalId = activeModal.id
      const elementToRestore =
        activeModal.id === this.modalRoot?.id ? this.previousActiveElement : null

      this.lastActiveModalId = activeModalId

      requestAnimationFrame(() => {
        const currentModal = this.getActiveModal()
        if (!currentModal || currentModal.id !== activeModalId) return

        if (
          elementToRestore &&
          elementToRestore.isConnected &&
          this.getFocusableElements(currentModal).includes(elementToRestore)
        ) {
          elementToRestore.focus()
          this.previousActiveElement = null
        } else {
          this.focusActiveModal(currentModal)
        }
      })
    }

    this.onKeydown = event => {
      if (event.defaultPrevented) return

      if (!this.modalRoot || !document.body.contains(this.modalRoot)) return

      const activeModal = this.getActiveModal()
      if (!activeModal) return

      const key = event.key
      const isMac = /Mac|iPhone|iPad|iPod/.test(navigator.platform)

      if (key === "Escape") {
        event.preventDefault()
        event.stopImmediatePropagation()
        const closeButton = activeModal.querySelector("button[aria-label='close']")
        closeButton?.click()
        return
      }

      if (key === "Enter" && activeModal === this.modalRoot) {
        const saveShortcutPressed = isMac ? event.metaKey : event.ctrlKey

        if (saveShortcutPressed) {
          event.preventDefault()
          const saveButton = document.getElementById("alert-rule-save")
          if (saveButton?.disabled) return

          if (typeof this.el.requestSubmit === "function") {
            this.el.requestSubmit()
          } else {
            saveButton?.click()
          }
          return
        }

        const tagName = event.target?.tagName?.toLowerCase()
        const type = event.target?.getAttribute?.("type")
        const isTextEntry = tagName === "input" && type !== "checkbox" && type !== "radio"

        if (isTextEntry) {
          event.preventDefault()
        }
      }

      if (key !== "Tab") return

      const focusables = this.getFocusableElements(activeModal)
      if (focusables.length === 0) return

      const first = focusables[0]
      const last = focusables[focusables.length - 1]
      const active = document.activeElement
      const activeIndex = focusables.indexOf(active)

      event.preventDefault()
      event.stopImmediatePropagation()

      if (activeIndex === -1) {
        ;(event.shiftKey ? last : first).focus()
        return
      }

      const nextIndex = event.shiftKey
        ? (activeIndex - 1 + focusables.length) % focusables.length
        : (activeIndex + 1) % focusables.length

      focusables[nextIndex].focus()
    }

    this.modalObserver = new MutationObserver(this.scheduleActiveModalFocus)
    this.modalObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ["aria-hidden", "class", "data-focus-target", "style"],
      childList: true,
      subtree: true,
    })

    window.addEventListener("keydown", this.onKeydown, true)
    window.addEventListener("focusin", this.onFocusIn, true)
    this.scheduleActiveModalFocus()
    requestAnimationFrame(this.scheduleActiveModalFocus)
    this.focusTimer = setTimeout(this.scheduleActiveModalFocus, 80)
  },

  updated() {
    this.scheduleActiveModalFocus()
  },

  destroyed() {
    if (this.onKeydown) {
      window.removeEventListener("keydown", this.onKeydown, true)
    }
    if (this.onFocusIn) {
      window.removeEventListener("focusin", this.onFocusIn, true)
    }

    this.modalObserver?.disconnect()
    if (this.focusTimer) clearTimeout(this.focusTimer)

    const focusReturnId = this.modalRoot?.dataset.focusReturnTarget
    if (!focusReturnId) return

    const restoreFocus = () => {
      const target = document.getElementById(focusReturnId)
      if (target && this.isVisible(target)) target.focus()
    }

    requestAnimationFrame(restoreFocus)
    setTimeout(restoreFocus, 80)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    ApexChart,
    TerminalHook,
    Fullscreen,
    CodeMirror: CodeMirrorHook,
    IndeterminateCheckbox,
    SchemaFieldInput,
    SchemaFieldSelect,
    ReportColumnTitle,
    ReportFilterValue,
    ReportNameAutofocus,
    ReportBuilderKeyboard,
    AlertRuleBuilderKeyboard,
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())
window.addEventListener("phx:focus_column_title", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const input = document.getElementById(id)
    if (!input) return

    input.focus()
    input.select()
  })
})
window.addEventListener("phx:focus_schema_field", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const select = document.getElementById(id)
    if (!select) return

    select.focus()
  })
})
window.addEventListener("phx:focus_schema_field_name", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const input = document.getElementById(id)
    if (!input) return

    input.focus()
    input.select()
  })
})
window.addEventListener("phx:focus_filter_field", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const select = document.getElementById(id)
    if (!select) return

    select.focus()
  })
})
window.addEventListener("phx:focus_filter_operator", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const select = document.getElementById(id)
    if (!select) return

    select.focus()
  })
})
window.addEventListener("phx:focus_filter_value", event => {
  const id = event?.detail?.id
  if (!id) return

  requestAnimationFrame(() => {
    const input = document.getElementById(id)
    if (!input) return

    input.focus()
    const end = input.value?.length ?? 0
    input.setSelectionRange(end, end)
  })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
