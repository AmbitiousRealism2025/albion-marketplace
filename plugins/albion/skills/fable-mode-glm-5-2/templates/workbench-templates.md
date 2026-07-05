# Workbench Templates

## `.agent-workbench/fable-mode/<task-slug>/task.md`

```markdown
# Task

Goal:
Done condition:
Permitted actions:
Forbidden actions:
Assumptions:
User-only blockers:
```

## `.agent-workbench/fable-mode/<task-slug>/state-map.md`

```markdown
# State map

Important entities/files/modules/APIs:

Overloaded terms to split:

Boundary conventions:

Competing interpretations:

Chosen interpretation:
```

## `.agent-workbench/fable-mode/<task-slug>/hypotheses.md`

```markdown
# Hypotheses

## H1
Claim:
Would be falsified by:
Smallest check:
Status:

## H2
Claim:
Would be falsified by:
Smallest check:
Status:
```

## `.agent-workbench/fable-mode/<task-slug>/evidence.md`

```markdown
# Evidence ledger

- Claim:
  Evidence:
  Source:
  Confidence:
```

## `.agent-workbench/fable-mode/<task-slug>/verification.md`

```markdown
# Verification

Commands run:
Results:
Known failures:
Checks skipped and why:
Independent verifier findings:
```

## `.agent-workbench/fable-mode/<task-slug>/counterexamples.jsonl`

```jsonl
{"hypothesis":"","case":"","failure":"","lesson":"","next_check":""}
```

## `.agent-workbench/fable-mode/lessons/example.md`

```markdown
# One-line lesson

Context:
Correction or confirmed approach:
Why it mattered:
When to reuse:
When not to reuse:
```
