function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[data-codemirror-src="${src}"]`)) {
      resolve()
      return
    }
    const script = document.createElement("script")
    script.src = src
    script.dataset.codemirrorSrc = src
    script.onload = resolve
    script.onerror = reject
    document.head.appendChild(script)
  })
}

let codemirrorPromise = null

function ensureCodeMirror() {
  if (!codemirrorPromise) {
    codemirrorPromise = (async () => {
      await loadScript("/codemirror/codemirror.min.js")
      await loadScript("/codemirror/codemirror-yaml.min.js")
      await loadScript("/codemirror/codemirror-python.min.js")
      return window.CodeMirror
    })()
  }
  return codemirrorPromise
}

function isDarkTheme() {
  const theme = document.documentElement.getAttribute("data-theme")
  if (theme) return theme === "dark"
  return window.matchMedia("(prefers-color-scheme: dark)").matches
}

const CodeMirrorHook = {
  async mounted() {
    this._destroyed = false
    const CodeMirror = await ensureCodeMirror()

    // The hook can be removed while CodeMirror is loading its vendor scripts.
    if (this._destroyed || !this.el?.isConnected) return

    const mode = this.el.dataset.mode || "yaml"
    const readOnly = this.el.dataset.readonly === "true"

    this.el.style.display = "none"

    this.container = document.createElement("div")
    this.container.className = "rounded-lg overflow-hidden border border-base-300"
    if (readOnly) this.container.classList.add("cm-readonly")
    this.el.parentNode.insertBefore(this.container, this.el)

    this.editor = CodeMirror(this.container, {
      value: this.el.value || "",
      mode: mode,
      theme: isDarkTheme() ? "material-darker" : "default",
      lineNumbers: !readOnly,
      lineWrapping: true,
      tabSize: 2,
      indentWithTabs: false,
      matchBrackets: true,
      autoCloseBrackets: !readOnly,
      readOnly: readOnly,
      cursorBlinkRate: readOnly ? -1 : 530,
      extraKeys: readOnly ? {} : {
        Tab: (cm) => cm.execCommand("indentMore"),
        "Shift-Tab": (cm) => cm.execCommand("indentLess"),
      },
    })

    this.editor.on("change", () => {
      this.el.value = this.editor.getValue()
    })

    this._syncValue = () => {
      if (this.editor) {
        this.el.value = this.editor.getValue()
      }
    }

    this._form = this.el.closest("form")
    if (this._form) {
      this._form.addEventListener("submit", this._syncValue)
    }

    this._themeObserver = new MutationObserver(() => {
      if (this.editor) {
        const dark = isDarkTheme()
        this.editor.setOption("theme", dark ? "material-darker" : "default")
      }
    })
    this._themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    })

    if (this.el.id === "front-matter-editor") {
      this.handleEvent("update_front_matter", ({ content }) => {
        if (this.editor && this.editor.getValue() !== content) {
          this.editor.setValue(content)
        }
      })
    }
  },

  updated() {
    const newValue = this.el.value || ""
    if (this.editor && this.editor.getValue() !== newValue) {
      this.editor.setValue(newValue)
    }
  },

  destroyed() {
    this._destroyed = true

    if (this._form) {
      this._form.removeEventListener("submit", this._syncValue)
      this._form = null
    }
    this._syncValue = null

    if (this._themeObserver) {
      this._themeObserver.disconnect()
      this._themeObserver = null
    }

    if (this.editor) {
      this.editor.getWrapperElement()?.remove()
      this.editor = null
    }

    if (this.container) {
      this.container.remove()
      this.container = null
    }

    if (this.el) {
      this.el.style.display = ""
    }
  },
}

export default CodeMirrorHook
