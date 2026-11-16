# The Status Nim style guide (digest)

- Source: https://status-im.github.io/nim-style-guide/ (read 2026-11-17; written for Nim 2.2).
- No licence was found in https://github.com/status-im/nim-style-guide (no LICENSE file in the
  repository). This digest therefore only paraphrases and links; nothing is quoted.
- Read: introduction, formatting (style, naming), language (imports, macros, object construction,
  ref object, memory, variable declaration and initialisation, proc/func, methods, proc types,
  result, return, inline, converters, finalizers, binary data).
- Not read: the integers chapter and everything after it (errors and exceptions, interop and FFI,
  tooling, libraries). nim-best-practices does not cite the guide for those topics.

## Principles

- Order of qualities: correct, readable, elegant, efficient. Safe defaults; consider the adversary.
- Document why when deviating from the guide; follow local conventions in older code.

## Formatting and naming

- Format with `nph` (88 columns), pinned in CI; not `nimpretty`. NEP1 otherwise.
- Never rely on style-insensitive identifiers; use `--styleCheck:usages` and `--styleCheck:error`.
- `ref object` types get a `Ref` suffix. Constructors `func init(T: type Xxx, …): T` and
  `func new(T: type Xxx, …): ref T`. Exceptions `XxxError` (CatchableError) / `XxxDefect`.

## Language

- Import a minimal set of modules by explicit path, grouped std, packages, local; re-export
  modules whose types appear in public symbols; avoid `include`.
- Macros sparingly; never to generate public API.
- Construct with `Xxx(field: …)` or an `init`; make the zero value valid.
- Avoid `ref object` except for resource handles, shared ownership, reference structures, or
  stable pointers for foreign code.
- Prefer stack and fixed-size types in low-level code; avoid `alloca`.
- Most restrictive of `const`, `let`, `var`; initialise with expressions.
- Prefer `func`; export only intended API; prefer `openArray` over `seq` parameters.
- Use `method` sparingly; consider a manual table of closures.
- Annotate proc types with `{.raises: [], gcsafe.}` or specific exceptions.
- Avoid `result` for returning values; use expressions, `return` for early exit.
- Avoid `{.inline.}`; rely on LTO.
- Avoid converters; do not use finalizers.
- `byte` / `seq[byte]` for binary data, not `string`.
