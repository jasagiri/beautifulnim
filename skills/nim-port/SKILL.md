---
name: nim-port
description: >-
  Port code written in C, C++, Python, Rust, Go, JavaScript or TypeScript to idiomatic Nim while
  keeping its observable behaviour, tests first. Use when asked to port, translate, convert,
  migrate or rewrite a module or program in Nim. Pairs with nim-best-practices, which says what
  the result should look like.
---

# Porting to Nim

The goal is Nim that a Nim programmer would have written, with the same observable behaviour as
the original — not the original's structure in Nim syntax.

## 1. Understand the original

- Read the code and its tests. List the observable behaviour: inputs, outputs, errors, side effects,
  edge cases (empty input, huge input, invalid UTF-8, overflow, missing files).
- Separate behaviour from accident: things that only exist because of the source language (manual
  memory management, a GIL workaround, Python's dict ordering, JavaScript's number type).
- Bugs are behaviour until told otherwise: keep them, mark them in a test, and list them.

## 2. Port the tests first

- One Nim test per original test, same name in Given-When-Then form, in `tests/` with
  `std/unittest`. If the original has no tests, write tests from the behaviour list before porting.
- Run them: all fail (nothing is implemented yet). That is the baseline.

## 3. Design the API, then implement

Decide the public types and procs first (guide section 4), then fill them in until the tests pass.

| In the original | In Nim |
|---|---|
| `NULL` / `None` / `null` / `undefined` | `Option[T]`, or a non-nilable value type |
| error codes, `errno` | a `CatchableError` subtype with `{.raises: [...]}`, or a result value |
| out-parameters (`int *out`) | return a tuple or an object |
| flag integers (`O_RDONLY | O_CREAT`) | `set[Flag]` |
| `bool` options on public functions | an enum, or two procs |
| `struct` + functions | `object` + procs with the object first |
| class hierarchy with virtual methods | object variant + `case`; `method` only for an open set |
| `malloc`/`free`, RAII, `Drop` | value types; `=destroy` for resources |
| `std::shared_ptr`, `Rc` | `ref` (only where sharing is real) |
| Python `dict` (insertion order) | `OrderedTable` when order is observable, else `Table` |
| Python `bytes`, JS `Uint8Array` | `seq[byte]` |
| JS `number` | `int` or `float` chosen per use; check ranges |
| Go `error` return | raise, or `Opt`/result value; never ignore it |
| Go goroutines + channels | threads + channels, or async; move data, do not share it |
| Rust `Result<T, E>` | exceptions with `raises`, or the `results` package if the project uses it |
| Rust traits | concrete procs, generics with type classes; concepts when needed |
| decorators, metaclasses, `eval` | templates and macros, only where a proc cannot do it |

## 4. Keep it proportionate

- Do not reimplement the source language's runtime (a `PyObject`, a JS event loop).
- Do not grow the API: port what exists, not what might be useful.
- Keep the algorithm unless it is the source of a listed bug; a faster algorithm is a separate change.
- Use the standard library first (`std/json`, `std/tables`, `std/strutils`, `std/os`), then
  well-known packages; say which and why.

## 5. Verify

- `nim check` clean with `lints/nim.cfg`, all ported tests green, `beautifulnim check
  --min-level:warning` with nothing to report (or a reason for each).
- Run both versions on the same inputs where possible and compare outputs byte for byte.

## 6. Write PORTING.md

- API mapping: each original function or type → its Nim counterpart.
- Test mapping: each original test → its Nim test.
- Deliberate differences, each with the reason (for example "raises ConfigError instead of
  returning -1").
- Preserved quirks and bugs, each pinned by a test.
- How it was verified: the commands and their exit codes.
