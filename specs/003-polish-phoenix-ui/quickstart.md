# Quickstart: UI Polish Verification

## Prerequisites
- Local Phoenix server running (`mix phx.server` in `packages/nixstasis/server`)

## Verification Steps

### 1. Layout & Responsive Check
1. Open http://localhost:4000
2. **Desktop (>1024px)**:
   - Verify Sidebar is visible on the left.
   - Verify content is centered/padded on the right.
3. **Mobile (<1024px)**:
   - Verify Sidebar is hidden.
   - Verify Bottom Navigation bar appears at the bottom of the screen.
   - Verify "Hamburger" menu opens the Sidebar (drawer overlay).

### 2. Theme Toggle
1. Click the theme toggle (Sun/Moon icon).
2. Verify the application colors switch between Light and Dark modes instantly.
3. Refresh the page; verify the selected theme persists.

### 3. Components
1. Navigate to a page with a table (e.g., Devices or Dashboard).
2. Verify the table uses the "Minimal/Flat" style (DaisyUI table).
3. Interact with buttons; verify hover states and ripples/transitions.

### 4. Notifications
1. Trigger an action that causes a flash message (e.g., save settings).
2. Verify a "Toast" notification appears in the top-right corner.
3. Verify it disappears automatically or has a dismiss button.
