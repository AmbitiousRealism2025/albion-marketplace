---
name: completion-gate
description: Load when the stop gate blocks twice on the same task. Do not load for ordinary unfinished work, first gate blocks, or reports where no completion claim is being made.
---

# Completion Gate

Extend charter §7 when the stop gate repeats. Treat the gate as a diagnostic, not a wording problem.

## Gate Conditions

| Condition | What it means | Honest resolution |
|---|---|---|
| Open tasks | Task tracking still has work not completed or blocked. | Complete the task, or mark it blocked with evidence and user-only dependency. |
| Failing `last_test` | The latest recorded validation failed. | Fix and re-run, or report the failure as remaining risk with exact output. |
| Empty `verification.md` on workbench tasks | No verification record exists for a task that required one. | Record checks run, results, skipped checks, and reasons. |
| Completion-claim heuristic | The final message claims done without enough evidence. | Remove the claim or add direct evidence from files, tests, or observations. |

## Resolution Steps

1. Read the gate message literally.
2. Identify the condition row.
3. Inspect the referenced task, test, or verification file.
4. Do the missing work if it is in scope.
5. If not in scope, hand back with evidence instead of forcing the gate.
6. Re-run the nearest validation before the next completion claim.

## Handback Format

Use only when the task genuinely cannot complete inside the contract.

```text
Blocked by:
Evidence:
What would unblock:
Work left untouched:
```

## Contract Rule

Satisfying the gate with hollow content violates charter contract rule 5. The gate is a floor, not the standard. A passing gate can still hide a false claim; remove the claim or verify it.
