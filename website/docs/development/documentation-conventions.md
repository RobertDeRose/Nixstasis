# Documentation Conventions

How this site is organized and how to write for it. Read this before adding or changing a page.

## What gets published

The site describes what Nixstasis does today. Plans, work in progress, and deferred ideas are tracked in Beads and
never appear on a published page.

A feature's directory under `website/docs/features/<slug>/` stays off the site until it has an `index.md`. That lets a
design be written and reviewed before the work ships; adding `index.md` at delivery publishes the design and the
delivery record together. [Feature Lifecycle](feature-lifecycle.md) covers the full process.

## Where things go

Put each page where a reader would look for it:

| If the reader is asking…                                         | Section              |
|------------------------------------------------------------------|----------------------|
| What is Nixstasis, and who is it for?                            | Introduction         |
| How is it put together, and why that way?                        | Architecture         |
| How do I deploy, run, monitor, or recover it?                    | Operations           |
| How do I build, test, change, or release it?                     | Development          |
| What exactly is this setting, field, command, limit, or default? | Reference            |
| What did a shipped feature add, and how did it differ from plan? | Implemented Features |

Keep each fact in one place and link to it from everywhere else, so the pages never disagree. Add a new page only
when it answers a question readers will keep asking, and register it in `website/sidebars.ts`.

When a feature ships, its design names the pages it changes. Those pages must make sense on their own: nobody should
have to read a feature design to understand how the product works.

## Module pages

Each page under Module Reference explains one part of the code using three sections:

- **Owns**: what the module is responsible for, and the source files it lives in.
- **Entry points**: the functions, routes, or commands other code uses to reach it.
- **Boundaries**: what it depends on, what depends on it, and the rules it enforces.

Describe how the module works rather than listing every function; the source files are linked for that. Operating
steps belong in Operations, and settings and wire formats belong in Reference.

## When docs and code disagree

If the docs, the code, the tests, or Beads disagree, open a Beads issue for it. Work out which side is wrong, fix
that side, and close the issue once everything matches again.

## Writing style

Write the way you would explain the system to a colleague who is new to it:

- **Start with what the reader can do.** Open a page or section with its purpose, not with a description of the page.
- **Use plain words.** Prefer "can be retried safely" to "idempotent", and explain any unavoidable term the first
  time it appears.
- **Say why.** When a rule would surprise someone, give the reason in a sentence.
- **Keep sentences short.** One idea per sentence; split a sentence that needs a semicolon to hold together.
- **Talk to the reader.** In guides and procedures, use "you" and number the steps.
- **Be exact where it matters.** Put commands, paths, settings, defaults, and limits in code formatting, tables, or
  code blocks, and keep them precise.
- **Link instead of repeating.** Point to the page that covers a topic; don't describe which page "owns" it.
