# Nixstasis Brand Guidelines
>
> **Context for LLMs/Agents:** Use this document to maintain visual consistency across the Nixstasis application. Adhere strictly to these tokens and patterns.

## 1. Core Identity

* **Application Name:** Nixstasis
* **Purpose:** IoT Device Manager & Monitoring
* **Visual Style:** Cobalt, Industrial, Professional, High-Contrast, Clean.
* **Logo:** Custom SVG.
  * *Default:* Cobalt/navy fill.
  * *Dark Mode:* Prefer light or blue-tinted logo artwork on dark cobalt surfaces. Use `dark:invert` only when the source asset is dark-only.

## 2. Color Palette (DaisyUI Themes)

The application uses **Tailwind CSS v4** with **DaisyUI**. Themes are defined in `assets/css/app.css`. The brand palette should match the AtomicNix cobalt theme in `/Users/DeRoseR/workspace/personal/AtonicNix/docs/theme/cobalt.css` and `/Users/DeRoseR/workspace/personal/AtonicNix/book/theme/cobalt-0aef8f6f.css`.

### Primary Colors

| Color Name | Hex Code | Variable | Usage |
| :--- | :--- | :--- | :--- |
| **Nixstasis Cobalt Black** | `#06102a` | `--color-base-100` (Dark) | Primary dark background and page shell. |
| **Nixstasis Deep Cobalt** | `#0b1a3a` | `--color-base-200` (Dark) | Sidebar, navigation, nested panels. |
| **Nixstasis Panel Cobalt** | `#132952` | `--color-base-300` (Dark) | Inputs, elevated surfaces, search fields. |
| **Nixstasis Ice** | `#d4e6ff` | `--color-base-content` (Dark) | Main foreground text on cobalt surfaces. |
| **Nixstasis Frost** | `#e7f3ff` | `--color-primary-content` (Dark) | High-emphasis headings and icon hover states. |
| **Nixstasis Electric Blue** | `#4ea3ff` | `--color-primary` | Primary actions, active navigation, focus states. |
| **Nixstasis Link Blue** | `#61b3ff` | `--color-info` | Links, informational affordances, secondary highlights. |
| **Nixstasis Glow Blue** | `#73c0ff` | `--color-accent` | Hover states, selected items, luminous borders. |
| **Nixstasis Muted Blue** | `#5d79a8` | `--color-neutral` | Disabled text, inactive controls, low-emphasis metadata. |
| **Nixstasis Border Blue** | `#203a66` | `--color-base-300` border usage | Table borders, card borders, dividers. |

### Theme Specifications

#### Light Mode (`data-theme="light"`)

* **Background (`base-100`):** `#f4f8ff` (Ice-tinted white)
* **Surface (`base-200`):** `#dbeaff` (Pale cobalt surface)
* **Elevated Surface (`base-300`):** `#c3dbff` (Sidebar frost)
* **Text (`base-content`):** `#06102a` (Nixstasis Cobalt Black)
* **Primary Action:** `#0b5fc7` (Accessible cobalt action blue)
* **Secondary Action:** `#1b3261` (Deep cobalt)
* **Accent:** `#376ec6` (Cobalt highlight)
* **Info:** `#4ea3ff` (Electric blue)
* **Error:** `#ff6b8a` (Use only for destructive/error states; do not use as a brand accent.)

#### Dark Mode (`data-theme="dark"`)

* **Background (`base-100`):** `#06102a` (Nixstasis Cobalt Black)
* **Surface (`base-200`):** `#0b1a3a` (Nixstasis Deep Cobalt)
* **Elevated Surface (`base-300`):** `#132952` (Nixstasis Panel Cobalt)
* **Text (`base-content`):** `#d4e6ff` (Nixstasis Ice)
* **Primary Action:** `#4ea3ff` (Nixstasis Electric Blue)
* **Secondary Action:** `#61b3ff` (Nixstasis Link Blue)
* **Accent:** `#73c0ff` (Nixstasis Glow Blue)
* **Neutral:** `#5d79a8` (Muted blue for disabled and inactive states)
* **Borders:** `#203a66` or `rgba(86, 141, 226, 0.32)`

### Background Treatment

Use a dark cobalt base with subtle blue radial glow when designing hero or empty states:

```css
background:
  radial-gradient(circle at 16% 8%, rgba(76, 146, 255, 0.2), transparent 36%),
  radial-gradient(circle at 86% 0%, rgba(50, 107, 206, 0.2), transparent 30%),
  #06102a;
```

Avoid red as a brand color. Reserve red/pink hues for validation errors, destructive actions, and alerts.

## 3. Typography

* **Font Family:** "Noto Sans" (Google Fonts).
* **Implementation:** Imported in `app.css` and set as the default sans font in Tailwind config.

## 4. UI/UX Patterns & Components

**Tech Stack:** Phoenix LiveView, Tailwind CSS v4, DaisyUI 5.

### Common Components

* **Modals:** Creation flows (e.g., "Add Device", "Add Alert", "Create Report") should be implemented as **Modals** (`CoreComponents.modal`), not separate navigation pages.
  * *Behavior:* Must close on `Escape` key.
  * *Styling:* Close button should use `text-base-content/60` (adaptive), not hardcoded gray.
* **Navigation:**
  * **Desktop:** Fixed Sidebar (DaisyUI Drawer).
  * **Mobile:** Top Navbar + Bottom Navigation Bar.
* **Cards:** Use DaisyUI `card` classes. Backgrounds should be `bg-base-100` or `bg-base-200` depending on nesting.
* **Icons:** Use the `CoreComponents.icon` component (Heroicons).
  * Example: `<.icon name="hero-home" class="size-5" />`

### System Behavior

* **Theme Toggle:** Supports "Light", "Dark", and "System" modes.
* **CSS Dark Mode Variant:** Tailwind's `dark:` variant is customized in `app.css` to trigger if:
    1. `data-theme="dark"` is explicitly set.
    2. No `data-theme` is set **AND** `prefers-color-scheme: dark` matches.

## 5. File Locations

* **CSS Config:** `packages/nixstasis/server/assets/css/app.css`
* **Layouts:** `packages/nixstasis/server/lib/nixstasis_web/components/layouts/`
* **Core Components:** `packages/nixstasis/server/lib/nixstasis_web/components/core_components.ex`
* **Logo:** `packages/nixstasis/server/priv/static/images/logo.svg`
