# NEP1 — Style Guide for Nim Code (digest)

- Source: https://nim-lang.org/docs/nep1.html (documentation of Nim 2.4.2, read 2026-11-17).
- Authors on the page: Clay Sweetser, Dominik Picheta. The page states no licence; the Nim
  repository is MIT except where a module says otherwise. This digest paraphrases; nothing is copied.
- Scope stated by NEP1: the standard library and official projects. Exceptions are allowed.

## Layout

- At most 80 characters per line; two-space indentation; tabs are rejected by the compiler.
- Avoid aligning with extra spaces: re-aligning by hand is tedious.
- Multi-line parameter lists, calls and tuples continue on an indented line; a double indent can
  separate a signature from its body.
- Ranges without spaces (`a..b`, `..<`, `..^`) unless the bound is an operator expression.
- Standard library imports use `std/` (`std/os`, `std/[os, strutils]`).

## Naming

- Types PascalCase; everything else camelCase; constants may be either. Variables start lowercase.
- C wrapper constants may be ALL_CAPS (called ugly but allowed).
- Value, `ref` and `ptr` varieties: the most used gets the plain name, others `Obj`/`Ref`/`Ptr`.
- Exceptions end in `Error` (from `CatchableError`) or `Defect` (from `Defect`); inheriting directly
  from `Exception` is called bad style.
- Enum values get a short prefix unless the enum is `{.pure.}`.
- Acronyms are ordinary words: `parseUrl`, `checkHttpHeader`.
- `m` prefix for routines giving mutable access (`mitems`, `mpairs`).
- In-place verb vs copying past participle (`sort`/`sorted`); `…In` for the in-place form when the
  copying form came first.
- subject-verb order: `fileExists`.
- Vocabulary: `initFoo` (value), `newFoo` (ref), `find` (index) vs `contains` (bool), `add`,
  `cmp`, `len`, `size` (bytes), `cap`, `items`/`pairs`, `del` vs `delete`, `incl`/`excl`.
- Getters `foo`, not `getFoo`, unless the call has side effects or is not O(1); likewise setters.

## Coding

- Use the implicit `result` whenever possible; `return` only for its control flow.
  (nim-best-practices sides with the Status guide for branching code; see SKILL.md section 6.)
- Prefer `proc`; use templates, macros, iterators and converters only when needed.
- `let` for values that do not change.

## Not covered by NEP1

Error handling beyond naming, effects, memory management, concurrency, FFI, tests.
