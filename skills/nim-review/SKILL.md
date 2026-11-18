---
name: nim-review
description: >-
  Review existing Nim code — a file, a module, a package, a diff or a pull request — for
  correctness, error handling, API design, idiom, memory and FFI safety, documentation and tests,
  and produce a prioritised report where every finding cites a rule and shows the smallest fix.
  Use when asked to review, audit, critique, grade or check Nim code, a .nim diff or a Nim PR.
  Pairs with nim-best-practices, whose sections the findings cite.
---

# Nim review

Read `skills/nim-best-practices/SKILL.md` first; this skill decides what to look at and how to
report it, that one says what good looks like.

## 1. Decide the scope

- What is under review: a file, a module, a package, or a diff (review the changed lines and what
  they touch, not the whole repository).
- Library or application (section 1 of the guide): libraries are held to the API rules, effect
  annotations and no global state; applications to clarity and error reporting.
- Nim version and memory manager (`nim -v`, the `requires "nim >= …"` line, `--mm`), and the
  project's own conventions (constructor style `initFoo` vs `Foo.init`, `results` vs exceptions,
  `asyncdispatch` vs `chronos`, formatter). Judge by those, and say where they differ from the guide.

## 2. Run the tools first

1. `nim check` on the files with the project's `nim.cfg`, then again with the lines of
   `lints/nim.cfg` added (with no project `nim.cfg`, `lints/nim.cfg` alone). When the code defines
   hooks, also `nim c`: `nim check` does not report a forbidden copy (nim-best-practices
   section 2). Every error is a finding. For a loose file, or a file whose name is not a
   Nim identifier, follow nim-best-practices section 2 (copy, `nim.cfg` next to it, `nim doc` when
   it has `runnableExamples`) and say in the summary which copy you checked.
2. `beautifulnim check --min-level:warning <files>` (the CLI in this repository). Each BN finding
   is a candidate; confirm it in context before reporting it.
3. The project's tests. A failing test is the first finding. If there are none, say so in the
   summary and name the behaviour a test should pin down.

Probes go through the public API and `import` the module. Only to reach private state, probe a copy of the module: either with the
probe under `when isMainModule:` at its end, or with the needed symbols exported and a separate
probe file importing it. Say in the summary that you did.

Report what the tools found as tool findings; do not re-derive them by reading. The tools miss
most correctness bugs: findings from reading go into the same tiers, and the summary says which
findings the tools caught and which came from reading.

## 3. Read, in this order

1. **Correctness and memory safety** — unchecked `Option.get`, object-variant fields read under the
   wrong `kind`, a collection changed while it is iterated (`del` inside `for … in t`), integer and
   range conversions from untrusted input, `cast`/`ptr`/`addr` without a
   soundness argument, a `cstring` outliving its `string`, missing `=destroy` or double ownership,
   `{.cast(gcsafe).}` hiding a data race, shared state without a lock.
2. **Error handling** — `except` that only discards (BN-01), `except Exception:`, exported procs
   without `raises`, exception types inheriting from `Exception`, errors turned into default values,
   `asyncCheck` on futures that can fail, destructors that raise.
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
<scope, library or application, Nim version, tools run and their exit codes>

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

- **Must fix**: wrong results, any `Defect` (crash) reachable from external input (valid or not)
  or from valid state, memory or thread unsafety, swallowed errors, security. A data race or a memory error you can show by
  reading the code is Must fix even when a probe does not reproduce it: such bugs depend on timing
  and the allocator. Say whether you reproduced it. Tier by the build the project ships, not
  `-d:danger`; when `-d:danger` turns the Defect into a silent wrong result, say so in the finding.
- **Should fix**: API and error-handling rules that will cost callers later.
- A doc comment that promises behaviour the code lacks is Should fix (section 10), Must fix when
  callers rely on it. When you cannot tell what the author meant, file it under Should fix with
  the question you need answered, instead of guessing a tier.
- **Consider**: idiom and style; at most a handful, grouped by kind rather than repeated per line.
- Every finding has a place, a rule and a fix. The rule is a BN ID or the closest section of
  nim-best-practices; when no section covers it, write `Rule: none in the guide` and state the
  mechanism (what fails, under which input). Do not report taste without a rule.
  Where the hard defects live in the guide: copies of a type with `=destroy`, hooks and moves in
  section 3; `addr`/`ptr` into a `seq` or `string` that later grows, `cast`, `UncheckedArray`,
  `cstring` lifetimes in section 8; threads, `{.cast(gcsafe).}` and `asyncCheck` in section 7;
  templates and macros under "Templates and macros" in section 4.
- "What is already good" is required; it tells the author what not to change.
- Write the review in the language of the pull request or the project's documentation; with
  neither, in the language of the request.

## 5. Offer the configuration

If the project has no `nim.cfg` settings like `lints/nim.cfg`, offer them as a separate change, with
the list of current violations each line would turn into errors.
