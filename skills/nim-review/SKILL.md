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
   `lints/nim.cfg` added. Every error is a finding.
2. `beautifulnim check --min-level:warning <files>` (the CLI in this repository). Each BN finding
   is a candidate; confirm it in context before reporting it.
3. The project's tests. A failing test is the first finding.

Report what the tools found as tool findings; do not re-derive them by reading.

## 3. Read, in this order

1. **Correctness and memory safety** — unchecked `Option.get`, object-variant fields read under the
   wrong `kind`, integer and range conversions from untrusted input, `cast`/`ptr`/`addr` without a
   soundness argument, a `cstring` outliving its `string`, missing `=destroy` or double ownership,
   `{.cast(gcsafe).}` hiding a data race, shared state without a lock.
2. **Error handling** — `except` that only discards (BN-01), `except Exception:`, exported procs
   without `raises`, exception types inheriting from `Exception`, errors turned into default values,
   `asyncCheck` on futures that can fail, destructors that raise.
3. **API design** — public `bool` parameters (BN-02), sentinels instead of `Option`, `ref` without a
   reason, `seq` parameters that could be `openArray`, `var` out-parameters instead of returned
   tuples, exported symbols that are not API, converters (BN-03), `method` for a closed set (BN-07),
   macros generating public procs.
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

- **Must fix**: wrong results, crashes, memory or thread unsafety, swallowed errors, security.
- **Should fix**: API and error-handling rules that will cost callers later.
- **Consider**: idiom and style; at most a handful, grouped by kind rather than repeated per line.
- Every finding has a place, a rule and a fix. Do not report taste without a rule.
- "What is already good" is required; it tells the author what not to change.

## 5. Offer the configuration

If the project has no `nim.cfg` settings like `lints/nim.cfg`, offer them as a separate change, with
the list of current violations each line would turn into errors.
