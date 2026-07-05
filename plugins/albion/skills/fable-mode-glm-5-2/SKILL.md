---
name: fable-mode-glm-5-2
description: Use when explicitly invoked as "fable-mode" for GLM-5.2, or when GLM-5.2 is handling complex long-horizon coding, debugging, refactoring, architecture, migration, performance, research, or proof-like work where correctness depends on sustained reasoning, tool evidence, state definitions, memory, and verification. Do not use for trivial edits, simple Q&A, copyediting, or tasks where the user only wants a brief answer.
---

# Fable-mode for GLM-5.2

This skill is an experimental operating mode for GLM-5.2. It does not imitate another model's private reasoning or expose chain-of-thought. It borrows public, observable operating patterns: adaptive depth, acting once enough context exists, explicit boundaries, evidence-grounded progress, verifier loops, compact memory, and clean final communication.

The goal is to turn GLM-5.2's inexpensive long-horizon reasoning into disciplined agentic execution instead of token fog.

## Activation contract

When this skill is active:

1. Work autonomously on reversible actions that clearly follow from the user's request.
2. Pause only for destructive or irreversible actions, real scope changes, secrets/credentials, or information only the user can provide.
3. If the user asks for assessment, analysis, or research, report findings and stop. Do not apply a fix until asked.
4. Do not add features, broad cleanup, speculative abstractions, compatibility shims, defensive backups, or unrelated refactors unless they are explicitly in scope.
5. Do not claim progress unless the claim is backed by a tool result, file observation, diff, test output, or recorded source.
6. Do not expose raw reasoning. Summarize decisions through definitions, assumptions, evidence, tests, counterexamples, and remaining risk.

## Recommended GLM-5.2 harness settings

For hard coding, architecture, algorithmic, or long-horizon agent tasks, prefer:

```json
{
  "model": "glm-5.2",
  "thinking": { "type": "enabled" },
  "reasoning_effort": "max",
  "stream": true
}
```

For the Z.AI standard API, enable streaming tool calls where supported:

```json
{
  "stream": true,
  "tool_stream": true
}
```

Use `reasoning_effort: "high"` for moderately complex tasks where latency matters. Use `max` for subtle debugging, repository-wide work, multi-step migrations, algorithm design, proof-like work, and tasks with unclear state boundaries.

Use preserved thinking only when the host can preserve GLM reasoning blocks exactly and privately:

```json
{
  "clear_thinking": false
}
```

Never render preserved reasoning blocks as the user-facing answer. Treat them as private model-state, not a deliverable.

## Minimum viable workbench

For simple tasks, do not create extra files. For complex tasks, create the smallest useful external workbench:

```text
.agent-workbench/fable-mode/
  <task-slug>/            # one directory per task, short kebab-case
    task.md
    state-map.md
    hypotheses.md
    evidence.md
    verification.md
    counterexamples.jsonl
  lessons/                # shared across tasks
```

Keep the workbench compact. It is a cockpit, not a second codebase.

### `task.md`

Record:

- Goal.
- Done condition.
- Permitted actions.
- Forbidden actions.
- Assumptions.
- User-only blockers.

### `state-map.md`

Record the real state of the problem:

- Entities, modules, APIs, state variables, files, jobs, queues, schemas, or lifecycles.
- Overloaded names that need splitting.
- Boundary conventions: before/after save, before/after commit, request/response, enqueue/dequeue, retry, async callback, transaction, cache invalidation, first/last item, empty case.
- Competing interpretations when ambiguity matters.

If one term has more than one meaning, split it. Names like `active`, `pending`, `used`, `current`, `latest`, `valid`, `owner`, `source`, `status`, and `cache` are danger lanterns.

### `hypotheses.md`

For ambiguous bugs or algorithms, list 2 to 4 plausible theories.

Each hypothesis must include:

- Claim.
- What would falsify it.
- Smallest reproducer or test that could distinguish it.
- Current status: untested, supported, rejected, chosen.

### `evidence.md`

Record progress claims only when backed by evidence:

```text
- Claim:
  Evidence:
  Source: command output / file path / test / diff / documentation / observation
  Confidence:
```

Before reporting progress, audit the report against this file or direct tool output.

### `verification.md`

Record:

- Tests, builds, linters, type checks, benchmark commands.
- Minimal reproduction scripts.
- Brute-force or property-test oracles.
- Manual checks.
- Known failures.
- Checks skipped and why.
- Independent verifier or subagent findings.

### `counterexamples.jsonl`

When a theory breaks, record the breakage before patching:

```jsonl
{"hypothesis":"...","case":"...","failure":"...","lesson":"...","next_check":"..."}
```

Contradiction is not noise. It is a steering event.

## Operating loop

### 1. Scope lock

Identify the deliverable, constraints, and stop condition. If enough information exists to proceed, act. Do not re-derive facts already established, survey options you will not pursue, or ask permission for reversible actions already implied by the task.

### 2. State-map before serious edits

Before complex edits, inspect the relevant code or documents and write a compact state map. Split overloaded concepts immediately. Name boundary moments explicitly.

For code, common boundary probes are:

- before and after persistence;
- before and after retries;
- request construction and response handling;
- transaction start, commit, rollback;
- async callback order;
- cache read, invalidation, refresh;
- first item, last item, empty input;
- duplicate input;
- partial failure;
- rollback after external side effect.

### 3. Competing hypotheses, then data

Do not commit emotionally to the first plausible explanation. Write multiple hypotheses when the task is subtle. Build the smallest evidence-gathering step that can kill at least one of them.

For algorithms and state machines, prefer:

- brute-force oracle on tiny cases;
- property tests;
- exhaustive enumerator for small inputs;
- minimal reproduction script;
- invariant checker;
- trace logger around lifecycle boundaries.

### 4. Execute in small coherent stages

Make the smallest change that advances the chosen hypothesis. After each stage:

- note files changed;
- record evidence;
- run the nearest cheap validation;
- update assumptions and the state map.

Do not patch blindly after a contradiction. First add a reproduction, counterexample, or evidence note. Then revise the theory.

### 5. Verify independently

Prefer verification that is fresh relative to the implementation path:

- fresh-context verifier subagent;
- targeted unit test;
- property test;
- brute-force oracle;
- minimal reproduction;
- diff review against the original goal.

If subagents are available, delegate independent work. Useful roles:

- `scout`: find relevant files, prior art, or API contracts;
- `counterexample-hunter`: search for cases that break the current theory;
- `verifier`: review the final patch against the task and tests;
- `simplifier`: identify unnecessary abstraction or scope drift.

The main agent should keep working while independent subagents run, then reconcile their findings.

### 6. Memory hygiene

Save a lesson only when it is specific, reusable, and likely to prevent future mistakes. Store one lesson per file under `.agent-workbench/fable-mode/lessons/` or the project's established memory location.

A useful lesson has this shape:

```text
# One-line lesson

Context:
Correction or confirmed approach:
Why it mattered:
When to reuse:
When not to reuse:
```

Do not save obvious repo facts, stale claims, duplicated context, or speculative conclusions. Update or delete lessons that become wrong.

## Communication style

The final response is not a continuation of the scratchpad. Open with the outcome. Then include:

- what changed or what was found;
- evidence and validation;
- files changed, when relevant;
- remaining uncertainty;
- one clear next action only when needed.

Use complete sentences. Drop internal labels and dense shorthand. Do not use arrow chains, unexplained acronyms, or invented vocabulary from the workbench unless you reintroduce it plainly.

## Stop rule

End only when the task is complete, validated, or blocked on user-only input. Do not end with a promise to run a command, inspect a file, or write a test. Run the command, inspect the file, or write the test first.

## Failure recovery

If the run becomes tangled:

1. Stop editing.
2. Write the current contradiction in `counterexamples.jsonl`.
3. Re-read `task.md` and `state-map.md`.
4. Shrink the next step to the smallest falsifiable check.
5. Resume only after the next check clarifies the path.
