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
the original — not the original's structure in Nim syntax. Read
`skills/nim-best-practices/SKILL.md` first; its section 0 decides when the task, the guides or the
setting disagree, and says which `details/` file to open for what is in front of you.

## 1. Understand the original

- Read the code and its tests. List the observable behaviour: inputs, outputs, errors, side effects,
  edge cases (empty input, huge input, invalid UTF-8, overflow, missing files).
- Separate behaviour from accident: things that only exist because of the source language (manual
  memory management, a GIL workaround, Python's dict ordering, JavaScript's number type).
- A limit of the source runtime that callers can see (Python's 4300-digit `int()` limit) is
  behaviour when the task asks for the same results on every input: keep it and list it. So is a
  data table of the runtime (which code points `str.isspace()`, `\d` or `str::trim` accept):
  generate it from the source runtime, write the generator command in PORTING.md, and check the
  port against the runtime over every code point.
- Bugs are behaviour until told otherwise: keep them, mark them in a test, and list them.
- A state the original can reach that the port cannot represent (a node kept after its `Weak`
  parent is gone) goes under deliberate differences, with how the original behaves in it.
- Error messages are behaviour when callers or the task read them. When the task names only the
  error type, match the type and list the message differences in the notes.

## 2. Port the tests first

- One Nim test per original test, same name in Given-When-Then form (a parametrized test, or one whose
  asserts check different behaviours, becomes a `suite` with the original's name and one test per
  case; the test mapping lists which is which), with `std/unittest`, in the
  project's `tests/`; with no project, in `tests/` beside the module, importing `../<module>` (nim-best-practices
  section 0); a task that shows `import <module>` describes its callers, not the tests. If the original has no tests, write tests from the behaviour list (its
  docstrings, its docs, or with neither the output the task names, then its code; say which) before
  porting; the notes map each clause to its test name. Test a behaviour only a private routine
  shows through the public routine, or give a program a public entry that takes its arguments and
  returns its output and exit code (`run(args)`); do not export the routine for the test.
- Run them against a stub that compiles under the same `nim.cfg` (no unused import): all fail, except tests the stub meets by accident (an
  empty result for empty input); list those. That is the baseline; save its output to a file in `probe/`.

## 3. Design the API, then implement

Decide the public types and procs first (guide section 4), then fill them in until the tests pass.

| In the original | In Nim |
|---|---|
| `NULL` / `None` / `null` / `undefined` | `Option[T]`, or a non-nilable value type |
| error codes, `errno` | a `CatchableError` subtype with `{.raises: [...]}`, or a result value |
| out-parameters (`int *out`) | return a tuple or an object |
| flag integers (`O_RDONLY | O_CREAT`) | `set[Flag]` in the Nim API; the C binding keeps the integer (`skills/nim-best-practices/details/ffi.md`) |
| `bool` options on public functions | an enum, or two procs |
| `struct` + functions | `object` + procs with the object first |
| class hierarchy with virtual methods | object variant + `case`; `method` only for an open set |
| `malloc`/`free`, RAII, `Drop` | value types; `=destroy` for resources |
| `std::shared_ptr`, `Rc` | `ref` (only where sharing is real) |
| C++ raw pointer or reference, Rust `&` / `&mut` | a plain parameter (a borrow) or a `var` parameter; an index into the owning `seq` when it is stored. Not `ref`, not a copy |
| Rust `.clone()`, a C++ copy constructor | a copy where the original copies; elsewhere a move or a borrow |
| `Rc<RefCell<T>>`, `Arc<Mutex<T>>`, a back pointer (`parent`) | one owner holding the values, indices elsewhere; a lock only for data the original shares between threads; a parent as an index or `{.cursor.}` |
| Python `dict` (insertion order) | `OrderedTable` when order is observable, else `Table` |
| Python `bytes`, JS `Uint8Array` | `seq[byte]` |
| JS `number` | `int` or `float` chosen per use; check ranges |
| Python `int` (unbounded) | `int`, with the bound checked before arithmetic can overflow (unchecked, overflow raises `OverflowDefect`). A result that does not fit raises the error the task names for bad input (`ValueError`), unless
  the original prints the same for every value past the bound (a count used as a limit): clamp it then (check by running the original at two values past the bound), and PORTING.md lists it as a deliberate difference: saturate every accumulator (each number and the running total) just past the bound, or check before multiplying, and keep the original's order of errors (for each input, the first error the original raises is the one the port raises; a guard must not make a later error fire first) |
| Python `str` (code points) | `string` (UTF-8 bytes); `std/unicode` runes where code points matter |
| Python generator | `iterator`; a closure iterator only when it is stored or passed. Its checks run at the first step, as Python's do at the first `next()` |
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
  well-known packages; say which and why. Where the port must match the original exactly, run a
  standard routine against the oracle on the input classes it will see before relying on it
  (`formatFloat` has no `%g` mode; `parseFloat` misreads literals over 494 digits in Nim 2.4;
  `std/unicode.validateUtf8` accepts surrogates and code points above U+10FFFF, which Python's
  decoder rejects).
  When it differs, use the nearest primitive that matches, or a small routine of your own when none does, keep the comparison as a test, and
  list the replacement under deliberate differences.

## 5. Verify

- `nim check` clean with `lints/nim.cfg`, all ported tests green, `beautifulnim check
  --min-level:warning` with nothing to report (or a reason for each; `--format:json` shows each
  file it parsed).
- When the original is fast by design (a game loop, a parser, an inner loop), a port that
  compiles and passes its tests can still copy or allocate on every iteration. Run the same
  workload on both, compare the allocation counts and the time
  (`skills/nim-best-practices/details/escape-hatches.md`), and list each new copy or allocation on
  the hot path in PORTING.md with its reason. Count the port's allocations with `-d:nimAllocStats` and the original's with its own
  tools (`heaptrack`, `valgrind`), or a copy of the original with a counting allocator added
  (Rust `#[global_allocator]`, a `malloc` wrapper in C) and say which events it counts (when the
  two sides count different events, such as `realloc`, compare only the ratio); when
  that is not possible, write the count read from its code and mark it as read, not measured.
  Time one pass over the workload (setup excluded), each side in its release build (`-d:release`,
  `rustc -O`, `-O2`; not `-d:danger`), at least 5 passes (in one process or several; say which; no warm-up pass unless you say so), and give the median with the minimum and maximum. Probes,
  benchmarks and builds of the original are not deliverables: keep them in `probe/` and name them under "How it was verified". The comparison is required when
  the task names a cost (a frame, a hot path, a size); a step that cannot run is "not run" with
  the reason (nim-best-practices section 0).
- Run both versions on the same inputs where possible and compare outputs byte for byte (write each
  side's stdout to a file and `cmp` them, or compare hashes when they are large). Match stdout and the exit status; stderr
  text only when the task names it. A comparison script exits non-zero on a difference not listed
  as deliberate. Code that reads untrusted input (a file, an argument or a network message a user supplies) also gets the checks of
  `skills/nim-best-practices/details/testing.md`, on the routine that parses, in process (the binary
  only for the exit status). An input both sides take with different results is a bug in
  the port: fix it and pin it in a test, unless it is a listed deliberate difference. List
  the inputs that only one side can take (invalid UTF-8 for a Python `str`, numbers past
  `int64`), and name the test that covers each. For an input only the port can take, choose
  what it does (the error and message the task names for bad input, or a stated result), pin it
  in a test, and list it under deliberate differences: no oracle can decide it. A task that says the source runtime "is not installed" means on the machine that
  runs the port: look for it where you work (`command -v python3 rustc cc node go`) and use it as
  the oracle when it is there. When the original cannot be run (section 0
  of the guide), mark each behaviour taken only from reading (a runtime limit) as unverified, with
  the command that would confirm it.

## 6. Write PORTING.md

Put it beside the port. When the task or the requester names another file for the notes, put
these sections there and write no second file.

- API mapping: each original function or type → its Nim counterpart.
- Test mapping: each original test → its Nim test.
- Deliberate differences, each with the reason (for example "raises ConfigError instead of
  returning -1").
- Preserved quirks and bugs, each pinned by a test.
- Working files (the copied `nim.cfg`, `probe/`) are not deliverables; name them.
- How it was verified: the commands and their exit codes (the command's own, not a filter's:
  `set -o pipefail`, or run it alone; a code you did not capture is "not captured").
