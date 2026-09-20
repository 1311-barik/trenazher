# Usability standard

How the engineering skills apply the usability standard in this repo. The standard governs
**behaviour** (what the user can do, undo and fix; screen states; gestures; errors; automation).
It outranks skill defaults wherever they disagree.

## Before designing or changing any user-facing behaviour, read these

- **`docs/USABILITY_STANDARD.md`**: the portable standard. Layers: `CORE` (never silently broken) →
  `PROFILE` (this product's decisions) → `DEFAULT` (proven approach, changeable with a reason) →
  `EXPERIMENT` (time-boxed hypothesis).
- **`docs/PRODUCT_USABILITY_PROFILE.md`**: this product's action/reverse matrix, screen states,
  product rules, visual system, experiments and deliberate deviations.
- **`docs/USABILITY_OBSERVATIONS.md`** and **`docs/EXPERIMENTS.md`**, when they exist.

If a file is missing, say so once and carry on; don't invent its contents.

## What each skill does differently here

- **`/grill-with-docs`, `/grill-me`**: for anything with a UI, also grill on the reverse action of
  every mutation, the screen states (loading / empty / error / partial / recovery after reload) and
  the main mobile path (standard §3, stages 3–5).
- **`/to-spec`**: every user story that changes state gets its reverse or corrective story in the
  same spec (standard §2.1: a feature with only the direct path is not finished). List new or
  changed rows of the action/reverse matrix under **Implementation Decisions**.
- **`/to-tickets`**: a tracer-bullet ticket carries the direct action **and** its reverse path
  together. Never split "undo" into a later ticket.
- **`/tdd`**: the reverse path is a behaviour like any other; it gets its own red → green slice.
- **`/prototype`** (UI branch): the visual direction comes from the `ui-ux-pro-max` skill and the
  product's `design-system/<slug>/MASTER.md`; behaviour comes from the standard. A prototype's
  marketing-style layout never becomes the first screen of a stateful product (standard §9.1).
- **`/code-review-spec`**: `docs/USABILITY_STANDARD.md` and `docs/PRODUCT_USABILITY_PROFILE.md` are
  standards sources for the **Standards** axis. A `CORE` breach is a hard violation; a `DEFAULT`
  deviation is a judgement call unless the profile records it as deliberate.
- **`/triage`**: classify incoming user signals with the standard's §18 vocabulary (`BUG`,
  `FRICTION`, `MISUNDERSTANDING`, `REQUEST`, `HYPOTHESIS`, `CONSTRAINT`) before assigning a triage
  role. One user comment is a signal to check, not a rule.
- **`/diagnosing-bugs`**: data loss or a dead-end after an error is a `CORE` breach; fix first,
  then record the observation.

## After the work

Update `docs/PRODUCT_USABILITY_PROFILE.md` when a decision changed. Only a portable behavioural
lesson goes back into the standard itself, following its §22 (bump version, changelog with the
reason, `CORE` untouched).
