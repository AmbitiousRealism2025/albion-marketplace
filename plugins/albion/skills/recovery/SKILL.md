---
name: recovery
description: Load on strike 3, a tangled run, or a contradiction that cannot be localized. Do not load for first failures, ordinary test red/green loops, or known environment outages.
---

# Recovery

Extend charter §3 (escalation) when the next edit would be guesswork. Stop edits until the contradiction is classified.

## Diagnosis Table

| Failure class | Symptom | Cheapest discriminating check |
|---|---|---|
| Theory wrong | Patch is coherent but outcome contradicts prediction | Build a minimal reproducer or oracle that isolates the claimed rule. |
| Edit wrong | Theory still fits, but implementation changed the wrong surface | Inspect diff against `task.md`; trace caller/callee or file ownership. |
| Test wrong | Product behavior is stable, assertion encodes stale or impossible rule | Compare test premise to docs, fixtures, and live behavior. |
| Environment wrong | Same inputs vary by shell, path, service, time, cache, or dependency state | Re-run in a clean env; print versions, paths, env keys, and fixture state. |

## Counterexample-First Procedure

1. Stop editing.
2. Write one JSONL entry in `counterexamples.jsonl`: hypothesis, case, failure, lesson, next_check.
3. Re-read `task.md`, `state-map.md`, and the latest diff.
4. Choose one row from the diagnosis table.
5. Run the cheapest discriminating check.
6. If the check rejects the row, update the counterexample and choose the next row.
7. Resume edits only after a row is supported and the next patch is local.

## Git Revert Criteria

Use revert as escalation only. Do not use it to escape uncertainty.

| Revert when | Do not revert when |
|---|---|
| The tree no longer matches `state-map.md` and re-deriving is cheaper than repair. | A single file or hunk can be inspected and corrected. |
| Edits cross the agreed scope fence and cannot be separated reliably. | Tests fail but the failure is localized. |
| Generated or bulk changes obscure the causal patch. | The user or another worker has unrelated changes in the tree. |

Before any git state change, pause for user approval unless the user explicitly authorized it.

## Escalation Format

```text
Attempted:
Evidence shows:
Decision needed:
```

Ask for one decision or one missing fact. Include the smallest command, file, or artifact that would unblock the run.
