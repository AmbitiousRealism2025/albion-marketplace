---
name: hot-path
description: Load before implementing anything that runs continuously or per-item at scale — animation and render loops, timers, pollers, per-request middleware, large-collection iteration. Do not load for one-shot scripts, setup code, or paths that run a bounded handful of times.
---

# Hot Path

Extend charter §4: code that runs continuously is verified by its cost, not
only its correctness. Before calling a hot path done, answer "what does one
iteration cost, and how often does it run?" — with a measurement, not an
estimate.

## Cost pass (run before verification)

| Question | Cheap check |
|---|---|
| What runs per frame/tick/request that could run once? | Hoist invariants out of the loop; cache what does not change between iterations |
| What is recomputed that could be baked? | Pre-render static visuals; memoize pure derivations; snapshot layout instead of re-measuring |
| What allocates per iteration? | Reuse buffers; move allocations outside the loop |
| What is per-iteration complexity against realistic n? | Measure with production-sized data, not toy fixtures |
| What does idle cost? | An idle loop should cost approximately nothing: coalesce timers, pause offscreen or occluded work |

## Rules

- A named budget in the acceptance criteria (fps, latency, CPU, memory) is
  satisfied only by a measurement against it. An architectural argument is a
  hypothesis, not a measurement.
- Measure on the production path with realistic data, and record the number
  in `verification.md`.
- Optimize the design first (what runs at all, and how often), constants
  second.
