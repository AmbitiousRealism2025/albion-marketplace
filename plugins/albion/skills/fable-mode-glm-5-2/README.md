# Fable-mode GLM-5.2 Experiment Pack

This pack contains an experimental `fable-mode` skill for GLM-5.2. It is designed for use in Codex-style or Claude-Code-style orchestration environments where GLM-5.2 is used as a secondary workhorse for coding, research, refactoring, debugging, and long-horizon agentic work.

The skill does not attempt to copy private chain-of-thought. It converts public Fable-like operating patterns into an external workbench and execution discipline: state mapping, boundary probes, hypothesis competition, counterexample logging, independent verification, compact memory, and clean user-facing summaries.

## Contents

- `SKILL.md`: the skill itself.
- `references/research-brief.md`: comparison of Fable and GLM-5.2, plus design rationale.
- `references/run-configs.md`: suggested GLM-5.2 runtime settings.
- `references/ab-test-plan.md`: experiment design for evaluating the skill.
- `templates/workbench-templates.md`: copy-paste templates for the workbench files.

## Suggested installation

For Codex, place the folder somewhere Codex can read as a skill, such as a repo-level `.agents/skills/fable-mode-glm-5-2/` or your global skills directory. For other agent harnesses, include `SKILL.md` as the invoked mode prompt and keep the references available for the orchestrator.

## First experiment

Start with a medium-complexity repo task where GLM-5.2 is already good but sometimes drifts: ambiguous bug hunt, state-machine fix, medium refactor with tests, or architecture audit. Run baseline GLM-5.2 first, then rerun with this mode and compare patch correctness, tests, time, token cost, scope drift, and final clarity.
