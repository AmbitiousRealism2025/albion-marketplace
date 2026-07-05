---
name: maturity-assessment
description: Load when entering an unfamiliar codebase, or before proposing an architecture-level change. Do not load for tiny edits, known local fixes, post-implementation summaries, or tasks already scoped by a current state-map.md.
---

# Maturity Assessment

Extend charter §3 (escalation) with a codebase maturity read. Record the result in `state-map.md` before architecture-level judgment or broad edits.

## Dimensions

| Dimension | Inspect | Signal |
|---|---|---|
| Tests / CI presence | `tests/`, CI configs, package scripts, fixture quality | validation surface and release discipline |
| Docs | README, architecture notes, runbooks, inline contracts | explicit intent vs inherited practice |
| Structure coherence | module boundaries, naming, layering, dead folders | local change cost |
| Dependency freshness | lockfile age, deprecated packages, security policy | upgrade pressure |
| Churn / age signals | recent commits, stale hotspots, ownership gaps | risk concentration |
| Hot paths | auth, persistence, migrations, queues, billing, deploy scripts | blast radius |

## Tiers

| Tier | Calibration | Do more of | Forbidden |
|---|---|---|---|
| Prototype | Low ceremony; behavior may outpace structure | small direct edits, cheap smoke checks, user-visible progress | process ceremony, framework rewrites, premature abstractions |
| Growth | Patterns exist but are uneven | align nearby code, add narrow tests around touched behavior | repo-wide normalization, hidden compatibility layers |
| Mature | Conventions are part of the product | match local contracts, preserve public shape, verify through existing gates | drive-by refactors, style churn, test weakening |
| Legacy | Behavior is valuable and under-specified | characterization tests before change, tiny reversible patches, explicit rollback notes | speculative cleanup, dependency jumps, unverified simplification |

## Assessment Block

Write at most 15 lines in `state-map.md`.

```text
## Maturity assessment
Tier:
Evidence:
- Tests / CI:
- Docs:
- Structure:
- Dependencies:
- Churn / age:
- Hot paths:
Behavioral calibration:
Forbidden at this tier:
Confidence:
```

If evidence conflicts, choose the lower-trust tier and name the contradiction.
