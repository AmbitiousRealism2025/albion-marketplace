---
name: delegation
description: Load when writing a subagent brief for non-trivial dispatched work. Do not load for direct edits, trivial lookups, user-facing summaries, or delegation already covered by an existing brief.
---

# Delegation

Extend charter §5 with dispatch packets that constrain work and make returned evidence reviewable.

## Brief Template

| Section | One-line guidance |
|---|---|
| TASK | State the exact question or artifact; one active verb. |
| EXPECTED OUTCOME | Name the returned object, format, and maximum size. |
| CONTEXT | Provide only facts needed to work; include relevant paths. |
| MUST DO | List required checks, readings, and evidence. |
| MUST NOT DO | Fence scope, forbidden files, and prohibited actions. |
| TOOLS ALLOWED | Name read/write/network/tool limits explicitly. |
| SUCCESS CRITERIA | Define the termination condition and return shape. |

## Guard Rails

- State a concrete termination criterion.
- Fence scope with named paths, modules, or documents.
- Forbid git state changes: no commits, checkouts, resets, rebases, stash, branch edits, or tag edits.
- Require evidence in the return: file lines, command results, reproduction steps, or inspected artifacts.
- Hide implementation narrative from `verifier` and `counterexample-hunter`; give task definition, artifacts, and expected behavior only.
- Limit secrets exposure: name environment variables or secret locations, never values.
- Require "not checked" labels for skipped checks with reasons.

## Parallel Dispatch

| Case | Rule |
|---|---|
| Independent reads | Dispatch in parallel; do not serialize. |
| Shared write target | Do not dispatch writes; split ownership or keep local. |
| Competing hypotheses | Assign one hypothesis per agent; require falsifier and result. |
| Verification | Use a fresh brief; omit the implementation path and your preferred explanation. |

## Reconciliation

1. Compare each return against its success criteria.
2. Mark evidence as observed, inferred, missing, or contradicted.
3. Resolve contradictions with the smallest direct check.
4. Update `state-map.md`, `hypotheses.md`, or `verification.md` before acting on the result.
5. Keep final judgment local; agents supply evidence, not authority.
