# ADR-BNIM-0001: Check rules on the tree Nim's own parser builds

**ADR ID**: ADR-BNIM-0001
**Status**: accepted
**Date**: 2026-11-17
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

BeautifulNim is a guide for agents that write, review and port Nim (`skills/`), compiler settings
(`lints/nim.cfg`), and a checker for the rules of the guide that a machine can decide
(`beautifulnim check`). The checker must never report text inside string literals or comments
(`docs/specification.md`). Line-based pattern matching, the usual way such checks are written,
cannot promise that.

## Decision

The checker walks the syntax tree that `compiler/parser.parseString` builds. That parser ships with
every Nim installation; the package reaches it with `--path:"$nim"`. Nothing is type-checked.

- A source that does not parse is not checked; the parser's own messages are returned (BN-P1).
- The parser's modules carry no `raises` annotations, so a call to it is inferred to raise
  `Exception`. `analyze` catches `Exception` at that one call and returns the message as a parse
  error, so `analyze` itself is `{.raises: [].}`.
- A rule the compiler already reports (for example `object of Exception`, `InheritFromException`)
  is not repeated by the checker; `lints/nim.cfg` turns that warning into an error.

## Alternatives

| Option | For | Against |
|---|---|---|
| Line-based pattern matching | small, fast | wrong inside strings, comments and multi-line declarations |
| A hand-written lexer | skips strings and comments | re-implements Nim's lexer (raw strings, nested `#[ ]#`, triple quotes): two owners of "what is Nim syntax" |
| **Nim's parser** (chosen) | reads code exactly as the compiler does, with the same error positions | `compiler/` is an internal API that can change between Nim versions |
| Full semantic check (`compiler`'s sem) | resolves names (a `bool` behind an alias) | must resolve imports and the standard library; slow; much larger |

## Consequences

- Rules are limited to what syntax decides. A `bool` parameter spelled through `type Flag = bool`
  is not reported by BN-02.
- The package requires `nim >= 2.4.2`; a new Nim version is checked with `nim test` before the
  requirement moves.
- The guide's examples are compiled in the tests (BN-X1), so the guide cannot drift from the
  language.

## Not decided

- Whether to add rules that need name resolution.

## 訂正 (2026-11-19)

- "Not decided: whether to add rules that need name resolution" is decided by ADR-BNIM-0003: BN-02
  can be decided on resolved types with `beautifulnim check --typed`. Without the flag this ADR
  still holds, including the consequence that `type Flag = bool` is not reported.
