# Implementation Plan - Polish Phoenix UI

**Branch**: `003-polish-phoenix-ui` | **Date**: 2026-02-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/003-polish-phoenix-ui/spec.md`

## Summary

This feature focuses on professionalizing the Phoenix application UI by implementing a consistent, responsive layout with a vertical sidebar (desktop) and bottom navigation (mobile), along with polished components and toast notifications using DaisyUI and Tailwind CSS.

## Technical Context

**Language/Version**: Elixir 1.19.5 (Phoenix 1.8+)
**Primary Dependencies**:
- `phoenix_live_view`
- `tailwind` (v4 import syntax)
- `daisyui` (already present in `assets/package.json` / `app.css`)
**Storage**: N/A (UI only, theme preference in local storage)
**Testing**: `ex_unit`, `phoenix_live_view_test`
**Target Platform**: Web (Responsive Desktop & Mobile)
**Project Type**: Monorepo Web Application (`packages/nixstasis/server`)
**Performance Goals**: Instant layout transitions (CSS-driven), <100ms interaction feedback
**Constraints**: Must use existing `app.css` structure; override `AGENTS.md` restriction on DaisyUI components.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance Check | Notes |
| :--- | :--- | :--- |
| **Quality & Simplicity** | ✅ | Using standard DaisyUI classes reduces custom CSS and maintenance burden. |
| **Behavior-Driven API** | N/A | Feature is purely UI; no new API endpoints. |
| **Targeted Unit Tests** | ✅ | Layout components will be tested for structure and responsiveness. |
| **User Experience First** | ✅ | Primary goal is to improve UX with better layout and feedback. |
| **Performance Compliance** | ✅ | CSS-driven layout ensures high performance. |

## Project Structure

### Documentation (this feature)

```text
specs/003-polish-phoenix-ui/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (N/A for this feature, but file created)
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A)
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
packages/nixstasis/server/
├── assets/
│   ├── css/
│   │   └── app.css          # Tailwind/DaisyUI config
│   └── js/
│       └── app.js           # Theme toggle logic (if JS needed)
├── lib/
│   └── nixstasis_web/
│       ├── components/
│       │   ├── layouts/
│       │   │   ├── app.html.heex    # Main layout (Sidebar/Drawer)
│       │   │   └── root.html.heex   # HTML shell
│       │   ├── core_components.ex   # Component polish (Table, Input, Button)
│       │   └── layouts.ex           # Layout logic & functional components
│       └── live/                    # Existing LiveViews (impacted by layout)
└── test/
    └── nixstasis_web/
        └── controllers/     # Layout tests
```

**Structure Decision**: Modifying existing Phoenix web structure within `packages/nixstasis/server`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*No violations.*
