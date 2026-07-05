---
name: conductor
description: Load for cross-session orchestration — dispatching work to an Albion/GLM worker over tmux, polling a worker completion manifest, or reviewing worker output. Do not load for in-session subagent delegation; use delegation instead.
---

# Conductor

Operate a stock-Claude-Code conductor over Albion workers. Tmux carries the run; files carry the truth.

## Dispatch

| Step | Rule |
|---|---|
| Brief | Write the packet with the 7-section template in the `delegation` skill; do not restate that template here. |
| Workspace | Start the worker in its own workspace tree. Keep the conductor tree clean until review. |
| Command | Run headless: `bin/albion -p "<brief>" --permission-mode acceptEdits --allowedTools "Bash(<narrow>:*)"` |
| Allowlist | Grant only task-shaped commands, such as `Bash(python3:*)` or `Bash(bash:*)`; never use `bypassPermissions`. |
| Tmux | One tmux session per dispatch for transport and observability only. Do not screen-scrape for status. |
| Signal | Require file outputs: changed tree, completion manifest, and worker final message. |

## Poll

| Check | Acceptance rule |
|---|---|
| Manifest path | Treat `${ALBION_MANIFEST_PATH:-$PWD/.albion/completion-manifest.json}` existence as the completion signal. |
| Schema | Validate against `state/schema.md` "Completion Manifest"; do not copy the schema into the brief. |
| Open work | Require `open_task_count == 0`. |
| Verification | Require every `workbench_tasks[].verification_present == true`. |
| Tests | Require `last_test != "fail"`; `unknown` is not proof, only a review input. |
| Caveat | A loop-guard-forced allow can also write a manifest, so content checks are mandatory. |

## Review Gate

| Gate | Rule |
|---|---|
| Scope | Compare the worker tree to the brief before reading conclusions. Out-of-scope edits fail review. |
| Diff | Read every hunk. The worker's self-report is not evidence. |
| Tests | Run the required tests yourself in the worker tree or integration tree, as appropriate. |
| Behavior | Probe actual behavior directly when the task has observable behavior. |
| Evidence | Accept only conductor-observed files, commands, and behavior. |
| Rework | Send a narrow follow-up brief; do not patch over unclear worker intent. |

## Recovery

| Stall state | Response |
|---|---|
| Tmux alive, no manifest | Inspect transcript for the last concrete action or blocker. |
| No file progress | Decide kill-and-redispatch vs. narrow follow-up brief from observed evidence. |
| Permission block | Relaunch only with the smallest allowlist that matches the blocked command class. |
| Contradictory output | Prefer a fresh worker brief over editing the worker tree mid-run. |
| Active run | Never edit the worker's tree while it is still running. |

## Release

| Artifact | Rule |
|---|---|
| Tmux | Kill the session after completion, failure, or abandonment. |
| Archive | Store the brief, completion manifest, and last message together. |
| Journal | Record tests run by the conductor, review findings, and rework decision. |
| Integration | Merge or copy only after the review gate passes. |
