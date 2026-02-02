# Research & Patterns

**Feature**: Polish Phoenix UI
**Status**: Completed

## DaisyUI Layout Patterns

### 1. Responsive Sidebar (Drawer)
**Decision**: Use DaisyUI `drawer` component with `lg:drawer-open`.
**Rationale**:
- **Mobile**: Acts as an overlay drawer (triggered by hamburger menu).
- **Desktop**: Fixes the sidebar to the left side (`lg:drawer-open`), pushing content to the right.
- **Implementation**:
  ```html
  <div class="drawer lg:drawer-open">
    <input id="my-drawer" type="checkbox" class="drawer-toggle" />
    <div class="drawer-content">
      <!-- Page content here -->
      <label for="my-drawer" class="btn btn-primary drawer-button lg:hidden">Open drawer</label>
    </div>
    <div class="drawer-side">
      <label for="my-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
      <ul class="menu p-4 w-80 min-h-full bg-base-200 text-base-content">
        <!-- Sidebar content here -->
        <li><a>Sidebar Item 1</a></li>
        <li><a>Sidebar Item 2</a></li>
      </ul>
    </div>
  </div>
  ```

### 2. Mobile Bottom Navigation
**Decision**: Use DaisyUI `btm-nav` component, visible only on mobile.
**Rationale**:
- Standard mobile app feel.
- **Implementation**:
  ```html
  <div class="btm-nav lg:hidden">
    <button class="active">
      <svg...>
      <span class="btm-nav-label">Home</span>
    </button>
    <!-- ... -->
  </div>
  ```
- **Constraint**: Need to ensure padding-bottom on the main content so the fixed nav doesn't cover content.

### 3. Toast Notifications
**Decision**: Use DaisyUI `toast` component for Flash messages.
**Rationale**:
- Replaces static alerts with ephemeral, non-blocking feedback.
- **Implementation**:
  ```html
  <div class="toast toast-top toast-end">
    <div class="alert alert-info">
      <span>New mail arrived.</span>
    </div>
  </div>
  ```
- **Integration**: Update `core_components.ex`'s `flash` component to render this structure.

## Theme Strategy
**Decision**: Manual Toggle with System Default.
- **Mechanism**:
  - Tailwind v4 `darkMode: 'selector'`.
  - JS stores preference in `localStorage` (`theme` = `light` | `dark` | `system`).
  - On load, apply `data-theme="light"` or `data-theme="dark"` to `<html>`.
  - Use `checkbox` with `theme-controller` class from DaisyUI for the toggle UI if possible, or custom JS dispatch.

## Component Polish
**Decision**:
- **Tables**: Class `table table-zebra table-compact`.
- **Inputs**: Class `input input-bordered w-full`.
- **Buttons**: Class `btn btn-primary` (and variants).
