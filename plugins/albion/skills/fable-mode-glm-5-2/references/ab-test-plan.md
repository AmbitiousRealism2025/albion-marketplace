# A/B Test Plan for Fable-mode GLM-5.2

## Purpose

Measure whether `fable-mode` improves GLM-5.2 on the user's real work, not just benchmark-shaped tasks.

## Conditions

Run each task under at least two conditions:

A. GLM-5.2 baseline with your normal prompt.
B. GLM-5.2 with `fable-mode-glm-5-2`.

Optional:

C. Fable or your current frontier baseline.
D. GPT-5.5 Pro/Codex baseline.

## Task set

Use 8 to 12 tasks:

- 2 repository audits.
- 2 medium refactors.
- 2 ambiguous bug hunts.
- 1 algorithm/invariant task.
- 1 performance optimization.
- Optional: 2 design/build tasks.

Prefer tasks with known acceptance criteria, existing tests, or a human-review rubric.

## Metrics

Record:

- Task completed: yes/no/partial.
- Tests passed.
- New tests added.
- Human correctness rating from 1 to 5.
- Scope drift: none/minor/major.
- Number of ungrounded progress claims.
- Number of useful counterexamples discovered.
- Time to first useful patch or deliverable.
- Total wall-clock time.
- Input/output/reasoning token cost where available.
- Final answer clarity from 1 to 5.

## Review questions

After each task, ask:

1. Did the skill prevent an error the baseline made?
2. Did the skill add unnecessary overhead?
3. Did the workbench contain useful durable state?
4. Did verification improve or merely become verbose?
5. Did final communication become clearer?

## Decision threshold

Keep the skill if it improves correctness or review confidence on complex tasks without unacceptable latency/cost. Tighten the trigger description if it helps hard tasks but annoys simple ones.
