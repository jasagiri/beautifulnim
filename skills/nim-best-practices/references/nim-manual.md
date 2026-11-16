# The Nim manual (digest of the sections the guide relies on)

- Source: https://nim-lang.org/docs/manual.html (documentation of Nim 2.4.2, read 2026-11-17;
  the page calls itself a draft). Authors: Andreas Rumpf, Zahary Karadjov. The page states no
  licence; the Nim repository is MIT except where a module says otherwise. Paraphrased.
- Read: identifiers, distinct types, ref and ptr, nil, mixing GC'd memory with ptr, func, methods,
  converters, the effect system, exception handling, type-bound operators.
- Also read: templates (typed and untyped parameters, hygiene, `inject`, `gensym`, `dirty`), and
  the opening of the macros chapter (how a macro is expanded, the style note).
- Not read in full: generics, the rest of the macros chapter, modules, pragmas (FFI, threads,
  guards and locks, out-parameters).

## Identifiers

- Only the first character is case-sensitive; the rest compare case-insensitively and ignore
  underscores. (The Status guide forbids relying on this; `--styleCheck:error` enforces it.)

## Types

- `distinct` makes a type with no subtype relation to its base; conversions both ways are explicit;
  `{.borrow.}` reuses the base's operations. The manual's examples: currencies, and an SQL string
  type that only explicit conversion can create.
- `ref` is traced, `ptr` is untraced and unsafe; `addr` is unsafe. Dereferencing `nil` is fatal.
- Manually allocated memory holding GC'd fields needs `reset` before `dealloc`, or they leak.
- The implicit `string` → `cstring` conversion is unsafe and announced for removal.
- Strings index bytes, not code points (`Rune` for those).
- Reading a field of an inactive object-variant branch raises `FieldDefect`.
- Objects are nominal, tuples structural; `{.requiresInit.}` prevents implicit zero initialisation.

## Procs, methods, converters

- `func` is a `proc` with `{.noSideEffect.}`.
- Returning a tuple is cleaner than `var` parameters, which are not needed for efficient passing.
- `f=` defines a setter usable as `x.f = v`. Routines returning `var` start with `m` in the stdlib.
- Procs dispatch statically, methods dynamically (on `ref` types); the root method needs
  `{.base.}`; generic methods are deprecated; multi-methods need `--multimethods:on`.
- Converters add implicit conversions; the manual's own example is labelled bad style.

## Exceptions and effects

- `Defect`s are bugs and strictly not catchable; `CatchableError` covers recoverable errors.
- The manual recommends ending custom exception names in `Error`.
- `{.raises: [...]}` is checked; `{.raises: [].}` means nothing escapes. Calls through proc types,
  forward-declared procs and methods are assumed to raise `Exception` unless annotated; `importc`
  procs are assumed to raise nothing. Defects are not tracked.
- `{.tags.}`/`{.forbids.}` track user-defined effects; `{.noSideEffect.}`; `{.gcsafe.}` means no
  access to globals holding GC'd memory; `{.cast(gcsafe).}` overrides the check.

## Templates and macros

- A template is substitution on syntax trees, done during semantic analysis. Its parameters are
  `untyped` (no lookup before substitution, so undeclared names may be passed), `typed`,
  `typedesc`, or ordinary types (which imply `typed`).
- Templates are hygienic: `var`, `let`, `const` and type names declared in one are `gensym`ed and
  invisible at the call site. Routines declared in one are `inject`ed. A name passed in as a
  parameter is injected. `{.dirty.}` turns hygiene off; `inject` and `gensym` then do nothing.
- A macro is run at compile time on the syntax tree of its arguments. Its result replaces the
  call and is analysed again, repeatedly while it contains further macro calls. Macros cannot
  change Nim's syntax.
- Style note: use the least powerful construct that stays expressive. In order: a proc or
  iterator, a generic one, a template, a macro.
