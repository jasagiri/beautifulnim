# ADR-BNIM-0002: Settle conflicts in one section and keep the main guide to one read

**ADR ID**: ADR-BNIM-0002
**Status**: accepted
**Date**: 2026-11-18
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

The guide (`skills/nim-best-practices/SKILL.md`) is improved by trials: a small model follows it on
three hard tasks (a port from Python, a C FFI module, a review with seeded defects). A hidden test
harness scores each task, and the executor lists the points where the guide made it stop
("blocked") or left it to choose. Each blocked point was fixed by adding a sentence where it came
up.

- Over seven rounds every task passed its harness, but the blocked count did not fall: 9, 10, 9,
  11, 9, 9, 7 [measured 2026-11-18]. Points that had been fixed did not return; new ones did.
- Of the 16 blocked points in rounds 6 and 7, 4 were missing Nim facts and 2 were vague terms;
  adding a sentence settles those. The other 10 were of three kinds that no single sentence
  settles [measured 2026-11-18]:
  - which wins when the task and the guide, or two rules of the guide, disagree (4);
  - a setting the guide assumed away: no project, a tool that hangs, a source that cannot be run
    (5);
  - the main file was cut off when read (1).
- One point (may a raises list be added to a signature the task fixed) was reported in four rounds,
  including after the answer had been written where it came up.
- The main file had grown to 42 352 characters; the executor's read stopped at 30 000
  [measured 2026-11-18].
- Executors also report "unsure I met the guide" as blocked, so the count has no floor.

The dominant criterion is fitness for purpose: an agent that follows the guide finishes the task
without stopping on the guide. Secondary criteria: one owner per rule (consistency), and no harness
regression when parts move out of the main file (risk).

## Decision

1. **Section 0 settles conflicts once.** The main guide opens with "When the task, the guide or the
   setting disagree": the task's explicit words win, and the guide still adds what keeps the task's
   call sites compiling (a raises list, `gcsafe`, docs), noted; the more specific rule wins, then
   the one that keeps a check; what the guide does not decide is chosen and noted, not a failure; a
   step that cannot run is recorded as not run; a loose file is a project of one. Sentences that
   answered one case of these (the notes file name, the added raises list) now point to section 0.
   `nim-port` and `nim-review` say to read it.
2. **Code-specific parts move to details files.** Ownership and hooks, templates and macros,
   concurrency, FFI and unsafe code, and fuzzing and memory tests move verbatim to
   `skills/nim-best-practices/details/`. The section they came from keeps a short summary and
   names the file to read before writing that kind of code. Section numbers do not change.
   `skills/nim-best-practices/references/` keeps its meaning: digests of the sources.
3. **Tests hold the layout.** BN-X1 to BN-X3 also cover
   `skills/nim-best-practices/details/*.md`. BN-X4: the main file is at most 28 000 characters,
   below the observed 30 000 cut. BN-X5: each skill names every file in its own details
   directory and names none that is missing.
4. **Trials count only what a machine can confirm as blocked**: a compile or test failure, a
   failed harness check, or a decision redone. "Unsure" is reported in its own list and does not
   count. Trials stop when every harness passes and blocked is 0 in two rounds in a row.

## Alternatives

| Option | For | Against |
|---|---|---|
| Keep adding a sentence per point | each fix is small and local | the count stayed at 7 to 11 for seven rounds; the file grew past one read; the same question returned after it was answered |
| Section 0 only, no split | one change | the main file stays over 40 000 characters and is still cut off |
| **Section 0, split into details files, layout tests, machine-confirmed counting** (chosen) | settles three kinds of point at once; the main file fits one read; the tests keep it so | an executor may skip a details file it needed |
| Rules-only main file, all prose in details files | shortest main file | most tasks would need several details files; the reasons behind the rules drift from the rules |

## Consequences

- An agent writing ordinary Nim reads one file; one writing FFI, hooks, macros, threads or memory
  tests reads one more, named in the section it is in.
- A details file that an executor skips shows up as a failed harness check, not as a blocked point;
  the trials after this change check for it.
- Growing the main file past 28 000 characters fails `nimble test`; new material goes into a
  details file or replaces old text.

## Not decided

- Whether `nim-review` and `nim-port` get details files of their own; they are under 9 000
  characters each.
- The trial tasks and harness live outside this repository; whether to publish them.
