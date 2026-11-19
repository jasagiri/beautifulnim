# ADR-BNIM-0005: Decide BN-05's foreign names and getters on the symbols in `check --typed`

**ADR ID**: ADR-BNIM-0005
**Status**: accepted
**Date**: 2026-11-19
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

BN-05 (NEP1 naming) runs on the syntax tree. Two of its answers depend on facts the tree does not
hold:

- A declaration keeps its foreign (C, C++, JavaScript) name when it is imported or exported. The
  syntax rule looks for `importc`, `importcpp`, `importjs` or `exportc` among the pragmas written on
  the declaration, so a name under `{.push importc.}`, or one that uses a `{.pragma: cfun, importc.}`
  alias, is reported although it must stay as the foreign library spells it.
- NEP1's "getters are named `foo`, not `getFoo`" is about reading a field or property of a value. The
  syntax rule reports any public `getFoo` with one parameter and a return type, so
  `getValue*(key: string)` is reported at level info although nothing is read from `key`.

ADR-BNIM-0003 left open whether BN-05 moves to the typed pass.

## Requirements

- Without `--typed`, BN-05 does not change.
- With `--typed`, a foreign name is recognised however the pragma reached the declaration.
- A `getFoo` finding stays only when the parameter is a value with fields.
- Names the syntax rule reports for other reasons (an uppercase routine, a lowercase type, `_`) stay.

## Options

| Option | For | Against |
|---|---|---|
| A. Teach the syntax rule `push` blocks and `{.pragma.}` aliases | works without `--typed` | a second evaluator of pragmas; misses pragmas from templates, macros and imported `{.pragma.}` definitions |
| **B. With `--typed`, keep the syntax rule's findings and drop those the symbol shows to be wrong** (`sfImportc`/`sfExportc`; the parameter's resolved type for `getFoo`) | the compiler's own answer; names keep one owner, the syntax rule | only with `--typed`; routines nested inside routines are not in the module's symbol table and keep the syntax verdict |
| C. Re-decide all of BN-05 on the symbols | one place for the typed answer | duplicates the name rules in two modules, and would need every nested symbol |

## Trade-offs

The dominating axis is one owner per question: the syntax rule owns "is this name NEP1", the
compiler owns "does this declaration have a foreign name" and "what is this parameter's type". B
asks each owner only its own question. A duplicates the compiler's pragma processing; C duplicates
the syntax rule.

## Decision

Option B (docs/specification.md BN-T7). A finding is dropped by place: the symbol's line and column
equal the finding's, since both point at the name.

## Consequences

- `check --typed` reports fewer BN-05 findings on C bindings and on `getFoo` procs that take a key.
- A `getFoo` whose parameter is a generic `T` is not reported with `--typed`: what `T` is depends on
  the caller.
- Routines nested inside other routines keep the syntax rule's verdict.

## Not decided

- Whether a routine named `getFoo` whose object has no field `foo` (a computed property) should be
  reported differently from one that reads the field.

## Rejected

- Option A: a second evaluator of pragmas, which the compiler already evaluates.

## 訂正 (2026-11-19)

- The open question under "Not decided" is decided (jasagiri, 2026-11-19: 欄を読むものと区別する). A `getFoo` whose parameter has the field `foo` (also inherited, compared as Nim compares names) is reported at level warning, since reading a field is never the expensive call the guide allows the prefix for (`skills/nim-best-practices/SKILL.md` section 4); a computed `getFoo` stays at level info. docs/specification.md BN-T7.
