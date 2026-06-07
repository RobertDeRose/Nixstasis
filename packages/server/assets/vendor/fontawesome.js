const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  let iconsDir = path.join(__dirname, "fontawesome/solid")
  let values = {}
  if (fs.existsSync(iconsDir)) {
    fs.readdirSync(iconsDir).forEach(file => {
      let name = path.basename(file, ".svg")
      values[name] = {name, fullPath: path.join(iconsDir, file)}
    })
  }
  matchComponents({
    "fa": ({name, fullPath}) => {
      let content = fs.readFileSync(fullPath).toString()
      content = content.replace(/<!--[\s\S]*?-->/g, "")
      content = content.replace(/\r?\n|\r/g, "")
      content = encodeURIComponent(content)
      let size = theme("spacing.4")
      return {
        [`--fa-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
        "-webkit-mask": `var(--fa-${name})`,
        "mask": `var(--fa-${name})`,
        "mask-repeat": "no-repeat",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block",
        "width": size,
        "height": size
      }
    }
  }, {values})
})
