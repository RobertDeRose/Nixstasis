<!--
Sync Impact Report:
- Version change: 0.0.0 -> 1.0.0
- Modified Principles: Established initial principles based on user input (Quality, BDD, Unit Tests, UX, Performance).
- Added Sections: Technology Standards, Development Workflow.
- Removed Sections: None.
- Templates requiring updates:
  - .specify/templates/tasks-template.md (✅ Updated to mandate tests)
- Follow-up TODOs: None.
-->
# Nixstasis Constitution

**Version**: 1.0.0 | **Ratified**: 2026-01-31 | **Last Amended**: 2026-01-31

## Core Principles

### I. Quality & Simplicity

Code MUST be clean, well-documented, and keep implementation simple when feasible. Complexity is a liability and MUST be
justified; documentation should explain the "why" behind complex logic.

### II. Behavior-Driven API Testing

APIs MUST have tests that follow behavior-driven development (BDD) patterns when feasible. Tests should describe the
expected behavior from the consumer's perspective (Given/When/Then).

### III. Targeted Unit Testing

Any complex functions MUST have unit tests that clearly define what they are testing. Unit tests should isolate complex
logic to ensure correctness and maintainability.

### IV. User Experience First

The user experience (UX) is a top priority. Technical decisions MUST NOT degrade the user experience unless absolutely
unavoidable and justified.

### V. Branding

All UX elements and designs MUST adhere to the `.specify/memory/branding_guidelines.md` whenever possible.
When not possible the design MUST do its best to keep to the spirit of the guidelines.
When the guidelines do not provide enough information or guidance, the existing styles used in the code SHOULD be used.
The file `.specify/memory/branding_guidelines.md` is meant to be a living document. When new styles have to be made
because there is nothing in the guidelines, a proposal should be made to add the new styles to the guidelines for
future developers.

### V. Performance Compliance

All features and changes MUST meet all performance requirements. Performance is a feature; regressions are treated as
bugs.

## Technology Standards

* **Language**: Elixir 1.19.5 with Erlang/OTP 28
* **Frameworks**: Phoenix 1.8+ with DaisyUI 5 using Tailwind CSS v4
* **Infrastructure**: Caddy (Reverse Proxy/TLS), FRP (NAT Punching), AuthCrunch (Auth)
* **Database**: Postgres for its built in support of storing JSONB and GINs

## Development Workflow

* **Specification-Driven**: All non-trivial changes start with a specification and plan using the project's `speckit` workflow.
* **Review Gates**: Code reviews MUST verify compliance with Core Principles (Simplicity, Testing, UX).
* **Testing Gates**: CI/CD pipelines (if applicable) or manual verification MUST pass relevant BDD and Unit tests before merging.

## Governance

This Constitution is the supreme authority for technical decision-making in the project.

* **Amendments**: Changes to this document require a Pull Request with a clear "Why" and incrementing the version number.
* **Compliance**: All contributions are subject to these principles. Deviations must be explicitly justified in the Implementation Plan.
* **Guidance**: For day-to-day execution, refer to the templates in `.specify/templates/`.
