---
name: nim-review
description: >-
  Review existing Nim code — a file, a module, a package, a diff or a pull request — for
  correctness, error handling, API design, idiom, memory and FFI safety, documentation and tests,
  and produce a prioritised report where every finding cites a rule and shows the smallest fix.
  Use when asked to review, audit, critique or check Nim code, a .nim diff or a Nim PR.
  Pairs with nim-best-practices, whose sections the findings cite.
---

# Nim review

Read `skills/nim-best-practices/SKILL.md` first; this skill decides what to look at and how to
report it, that one says what good looks like. Its section 0 decides when the task, the guides or
the setting disagree.

## 1. Decide the scope

- What is under review: a file, a module, a package, or a diff (review the changed lines and what
  they touch, not the whole repository).
- Library or application (section 1 of the guide): libraries are held to the API rules, effect
  annotations and no global state; applications to clarity and error reporting. A module inside
  a service is application code, unless other packages import it. With no project, the file is a
  project of one (nim-best-practices section 0): library rules when the request says other code
  imports it, application rules otherwise, tiered by the default build (section 4).
- Nim version and memory manager (`nim -v`, the `requires "nim >= …"` line, `--mm`), and the
  project's own conventions (constructor style `initFoo` vs `Foo.init`, `results` vs exceptions,
  `asyncdispatch` vs `chronos`, formatter). Judge by those, and say where they differ from the guide.

## 2. Run the tools first

1. `nim check` on the files with the project's `nim.cfg`, then again with the lines of
   `lints/nim.cfg` added (with no project `nim.cfg`, one run with `lints/nim.cfg` copied as
   `nim.cfg` next to a copy of the files; when the project's `nim.cfg` already is that copy, one
   run covers both). `--skipProjCfg` leaves out the `nim.cfg` next to the files and
   `--skipParentCfg` those of the directories above, for a run without them. When the code defines hooks, also `nim c` a driver that
   calls every exported routine: `nim check` does not report a forbidden copy, and `nim c` checks
   only the routines a program calls, so `nim c` of the module alone checks none (nim-best-practices section 2). Every error is a finding. For a loose file, or a file whose name is not a
   Nim identifier, follow nim-best-practices section 2 (copy, `nim.cfg` next to it, `nim doc` when
   it has `runnableExamples`) and say in the summary which copy you checked.
2. `beautifulnim check --min-level:warning --typed <files>` (the CLI in this repository). `--typed`
   checks each file as `nim check` does, so a `bool` behind an alias (`type Flag = bool`) counts
   for BN-02; when the files do not compile yet, drop `--typed` and report the compile errors from
   step 1. Report the `--typed` run; a run without it misses those aliases. Each BN finding is a candidate;
   confirm it in context before reporting it.
3. The project's tests. A failing test is the first finding. If there are none, say so in the
   summary and name the behaviour a test should pin down.
4. Ported or generated code, or code on a hot path: a green build and green tests are not the
   acceptance. List each copy, `ref`, `cast` and `cast` pragma the change adds and the check it
   gets past, and count the allocations of the hot path (`-d:nimAllocStats`), against the
   original when there is one.

Probes go through the public API and `import` the module. Only to reach private state, probe a
copy of the module under a new name (`ledger_probe.nim`) with the needed symbols exported, and a
separate probe file that imports it; leave the module itself unchanged. Say in the summary that
you did. Put probes in their own directory: every file next to a copied `nim.cfg` is checked
under it, so an unused import in a probe becomes an error.

Report what the tools found as tool findings; do not re-derive them by reading. The tools miss
most correctness bugs: findings from reading go into the same tiers, and the summary says which
findings the tools caught and which came from reading.

## 3. Read, in this order

1. **Correctness and memory safety** — unchecked `Option.get`, object-variant fields read under the
   wrong `kind`, a collection changed while it is iterated (`del` inside `for … in t`;
   the fix collects the keys first, then deletes), integer overflow in sums of amounts from
   outside, meaning any value a caller of a public proc or an external input supplies (a Defect,
   so Must fix), integer and
   range conversions from untrusted input (the fix: parse, check the bounds, then convert;
   nim-best-practices section 5), `cast`/`ptr`/`addr` without a soundness argument, a `cstring` outliving its `string`, missing `=destroy` or double ownership,
   `{.cast(gcsafe).}` hiding a data race, shared state without a lock. A change that only gets a
   check to pass: a copy of a value that is used again (a `=copy` inside a loop under
   `--expandArc`), a `ref` with one owner, a module-level `var`, `{.cast(noSideEffect).}` or
   `{.cast(raises: []).}`. A cycle nothing frees in time: an `{.acyclic.}` type whose values can
   reach themselves, a closure that captures the object holding it
   (`skills/nim-best-practices/details/escape-hatches.md`).
2. **Error handling** — `except` that only discards (BN-01), `except Exception:`, exported procs
   without `raises`, exception types inheriting from `Exception`, errors turned into default values,
   `asyncCheck` on futures that can fail, destructors that raise, an `except` for a subtype after
   one for its parent (it never runs; `skills/nim-best-practices/details/pitfalls.md`).
3. **API design** — public `bool` parameters (BN-02), sentinels instead of `Option`, `ref` without a
   reason, `seq` parameters that could be `openArray`, `var` out-parameters instead of returned
   tuples, exported symbols that are not API, converters (BN-03), `method` for a closed set (BN-07),
   macros generating public procs, a template or macro where a proc would do, a template that
   evaluates an argument more than once (BN-10), dirty templates (BN-08), code built from strings
   with `parseStmt` (BN-09), macros that accept any input without checking its shape.
4. **Idiom and clarity** — NEP1 names (BN-05), `result` assigned in every branch instead of an
   expression, `include` (BN-06), imports without `std/`, magic numbers, `string` for binary data,
   warnings switched off (BN-04).
5. **Documentation and tests** — `##` on exported symbols, `runnableExamples`, tests for the
   behaviour that changed, tests that restate the implementation instead of a property.

## 4. Report

```text
## Summary
<scope, library or application, Nim version (one line, from `nim -v`), and each command that
checks something (nim check, beautifulnim, a build, a test, a probe, a sanitizer run) with its exit code>

## Must fix
- <file>:<line> — <what is wrong and what it causes>. Rule: <guide section or BN-NN>.
  Fix: <the smallest change, as a code snippet>

## Should fix
- …

## Consider
- …

## What is already good
- <specific things worth keeping, with file:line>
```

- **Must fix**: wrong results; a crash reachable from external input (valid or not), from valid
  state or from a valid call order, whether it is a `Defect` or happens below Nim (a segfault on a
  `nil` passed to C, C undefined behaviour); memory or thread unsafety; swallowed errors; security;
  code that does not compile in a build the project ships (a forbidden copy that only `nim c` of a
  caller shows counts); memory that is never freed (a cycle of an `{.acyclic.}` type, any cycle
  under ARC, when the project ships ARC); an effect hidden by a `cast` pragma (a global write under `{.cast(noSideEffect).}`).
  A cycle that ORC frees only at its next collection is Should fix when the project ships ORC. The fix for a `Defect` that external input can reach, or a value the
  caller cannot check before the call (a sum that overflows), is to check the value and raise a
  `CatchableError` (nim-best-practices section 5), not to document the `Defect`. A precondition
  the caller can check (an index below `len`) may stay a `Defect` named in the `##` comment, as
  built-in indexing and `skills/nim-best-practices/details/ownership.md` do; a missing check or a missing `##` line is the finding then. Swallowed means a
  failure the caller needs never reaches it: an `except` that discards (BN-01), or bad input
  replaced by a default or skipped without a word in the doc comment. A data race or a memory
  error you can show by reading the code is Must fix even when a probe does not reproduce it:
  such bugs depend on timing and the allocator. Say whether you reproduced it.
- Tier by the build the project ships (the default build, checks on, when nothing says
  otherwise), not `-d:danger`. When `-d:danger` turns the Defect into a silent wrong result, say
  so in the finding.
- **Should fix**: API and error-handling rules that will cost callers later; a `func` that writes
  through a `ref` its parameters reach, with no `cast`; a copy or allocation per iteration on a
  hot path that you measured (Consider when only read).
- A `raises` list does not track Defects, so `raises: []` on a proc that can hit one is legal:
  the finding is the reachable Defect, not the annotation. A missing `##` or a missing `raises` list
  on an exported routine is Should fix.
- A doc comment that promises behaviour the code lacks is Should fix (section 10), Must fix when
  callers rely on it. When you cannot tell what the author meant, file it under Should fix with
  the question you need answered, instead of guessing a tier. This fallback is for code and doc
  that disagree; bad input skipped while the doc comment says nothing is swallowed (Must fix).
- **Consider**: idiom and style; at most a handful, grouped by kind rather than repeated per line.
- Every finding has a place, a rule and a fix. The fix is a code snippet; when the change is to a
  doc comment, the snippet is the new comment; when only the author can decide, write the question
  and a snippet for each answer you would accept; when the change is not code (tests to add, a
  config to adopt), the snippet is that text: a test's name and its check, the config line. A Consider item that groups several lines names
  one `file:line` and says "and similar". The rule is a BN ID or the closest section of
  nim-best-practices; when no section covers it, write `Rule: none in the guide` and state the
  mechanism (what fails, under which input). Do not report taste without a rule.
  Where the hard defects live in the guide: copies of a type with `=destroy`, hooks and moves in
  section 3 and `skills/nim-best-practices/details/ownership.md`; `addr`/`ptr` into a `seq` or
  `string` that later grows, `cast`, `UncheckedArray`, `cstring` lifetimes in section 8 and
  `skills/nim-best-practices/details/ffi.md`; threads, `{.cast(gcsafe).}` and `asyncCheck` in
  `skills/nim-best-practices/details/concurrency.md`; templates and macros in
  `skills/nim-best-practices/details/templates-and-macros.md`; shortcuts past a check, cycles and
  per-frame copies in `skills/nim-best-practices/details/escape-hatches.md`.
- "What is already good" is required; it tells the author what not to change.
- Write the review in the language of the pull request or the project's documentation; with
  neither, in the language of the request.

## 5. Offer the configuration

If the project has no `nim.cfg` settings like `lints/nim.cfg`, offer them as a separate change, with
the list of current violations each line would turn into errors.
