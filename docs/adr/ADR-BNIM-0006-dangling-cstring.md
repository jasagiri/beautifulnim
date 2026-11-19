# ADR-BNIM-0006: Report a returned `cstring` whose string is freed on return (BN-12)

**ADR ID**: ADR-BNIM-0006
**Status**: accepted
**Date**: 2026-11-19
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

A `cstring` does not own its bytes (`skills/nim-best-practices/details/ffi.md`). A routine that
returns `cstring(s & "\0")` hands out a pointer into a temporary string that is freed when the
routine returns [measured: AddressSanitizer reports heap-use-after-free on Nim 2.4.2 with
`-d:useMalloc`]. The compiler warns only about implicit conversions (`CStringConv`, made an error by
`lints/nim.cfg`); an explicit `cstring(…)` passes. An agent wrote exactly this in the review
scenario this checker was tuned on.

## Requirements

- Report the cases where the string is certainly freed on return: a temporary, a local variable of
  the routine, a `sink` parameter.
- Do not report strings the caller keeps alive (a plain parameter and its fields), globals or literals:
  the guide's advice there is "keep the string alive", which the routine cannot judge.
- Know what `result` is assigned after `return x` and an expression body, and what a name refers to.

## Options

| Option | For | Against |
|---|---|---|
| A. Syntax rule on `cstring(…)` in a routine whose return type is written `cstring` | no compiler | cannot tell a local from a global or a parameter, nor a `sink` parameter behind an alias; misses `return` through templates |
| **B. Typed rule: walk the semantically checked body for assignments to `result` of a `cstring` conversion and classify its source by symbol kind and owner** | the compiler resolves names, folds expression bodies and `return x` into `result = x` | only with `--typed`; a local initialised by a constant expression is reported though the compiler folds it to a literal |
| C. Escape analysis through calls (a `cstring` stored in a field, passed out through `var`) | covers more | a second lifetime analysis next to the compiler's; false positives the guide does not ask for |

## Trade-offs

The dominating axis is the precision of an error-level finding: a dangling pointer is never kept for
a reason, so the rule must report only certain cases. B is precise on the cases it covers and costs
only a tree walk in the pass `--typed` already runs; A cannot be precise without names; C trades
precision for coverage.

## Decision

Option B, rule BN-12 at level error (docs/specification.md BN-T8). Earlier the plan was level
warning, because a broader rule would have had false positives; restricted to certain cases, error
fits the rule's meaning ("the guide forbids it").

## Consequences

- `cstring` values that escape other ways (stored in a field, through a `var` parameter, from a
  nested routine) are not reported.
- A local `let s = "a" & "b"` (folded to a literal) followed by `result = s.cstring` is reported; the
  fix (return the string) is right anyway.

## Not decided

- Option C.

## Rejected

- Option A: it would need names, which only the compiler resolves.
