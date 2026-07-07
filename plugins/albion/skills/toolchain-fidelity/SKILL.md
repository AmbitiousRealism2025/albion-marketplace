---
name: toolchain-fidelity
description: Load before hand-writing or hand-editing files a toolchain normally generates or owns — Xcode project files, lockfiles, generated schemas or migrations, IDE workspace files. Do not load for ordinary source code.
---

# Toolchain Fidelity

Extend charter §4: a generated-format file is correct only if its owning tool
accepts it — linting is a floor, not the standard.

## Rules

- Prefer the generating tool over hand-writing. If the environment has the
  generator (project scaffolds, package managers, schema generators), use it
  and modify its output minimally.
- A hand-written or hand-edited generated-format file must round-trip through
  its owning tool before verification: open it, build with it, or validate
  with it, and record that check in `verification.md`.
- Do not invent keys or structure by analogy. Copy from a tool-generated
  reference or the format's documentation, and cite which on the board.
- A setting that fights the platform default (manual signing, disabled
  automatic schemes, pinned generated versions) needs its reason recorded in
  `task.md` — otherwise the default stands.
