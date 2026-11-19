---
name: nim-best-practices
description: >-
  Write, review, refactor or explain Nim code the way experienced Nim programmers do.
  Use whenever the task touches Nim: .nim, .nims or .nimble files, nimble, nim c / nim check,
  ARC/ORC, destructors and move semantics, sink/lent, raises and other effects, distinct types,
  object variants, Option, templates and macros, async, threads, FFI with importc — even when
  the request never says "best practices". Distilled from NEP1, the Nim manual, the destructors
  document and the Status Nim style guide; where they disagree this file picks one and says why.
---

# Nim best practices

Distilled from four sources (digests in `references/`): NEP1, the Nim manual, the destructors and
move semantics document (all at Nim 2.4.2), and the Status Nim style guide. Where they disagree,
this file says which to follow and why. Rules a machine can check carry an ID (BN-01…) and are
reported by `beautifulnim check` (the CLI in this repository); rules the compiler checks are
switched on in `lints/nim.cfg`. This file is about 28 000 characters: if your reader cuts it
off, read the rest by line range before you start.

## 0. When the task, the guide or the setting disagree

- **The task's explicit words win**: file names, signatures, keywords (`proc` or `func`), output
  format. A rule of this guide still applies when it only adds to them and the call sites the task
  describes still compile (a `raises` list, `gcsafe`, a doc comment); name each addition in your
  notes.
- **Two rules of the guide pull apart**: the one about the construct in front of you wins over the
  general one; if that does not decide it, take the one that keeps a check or reports an error.
- **The guide does not decide**: choose, write the choice and the reason in your notes, and go on.
  That is not a failure.
- **A step cannot run** (no project, a tool that fails or hangs, a program you may not run, a
  directory you may not write outside): write "not run" with the reason and what you did instead,
  and go on.
- **No project**: treat the file as a project of one: a copy of `lints/nim.cfg` next to it
  (section 2), tests in `tests/` beside it run with `nim c -r` (section 11), probes in a
  directory of their own, importing the module as `../<module>`.
- **Details**: read the `details/` file a section names before writing that kind of code;
  `details/ffi.md` before `importc`, a C callback, `cast` or `ptr`.

## 1. Mindset

- **Write Nim-shaped code**, not Java, C++ or Python translated line by line. Data is plain
  `object`s with value semantics; behaviour is procs called with method syntax (`p.area`);
  a closed set of shapes is an object variant; absence is `Option[T]`; resources are released by
  destructors. Class hierarchies with `ref object of RootObj` and `method` are the exception.
- **Make invalid states unrepresentable.** An `enum` instead of a `bool` flag, a `distinct` type
  for a unit or an ID, a `range` for a bounded number, an object variant instead of fields that are
  "only valid when kind is X". Validate once at the boundary, in a constructor.
- **Application code is not library code.** Libraries keep a small exported surface, annotate
  effects, avoid global state and never pick the async runtime or allocator for their caller.
  Applications may use concrete types, a top-level `except CatchableError` with logging, and
  whichever runtime they chose.
- **Let the compiler work.** `nim check` for errors, `--styleCheck:error` for spelling, the effect
  system (`raises`, `gcsafe`, `func`) for what a proc may do, `case` without `else` for exhaustive
  enums. A check the compiler performs is worth more than a convention in a comment.

## 2. Before you hand back code

- Run `nim check` on what you changed, the project's tests (`nimble test` or its own task), and
  `beautifulnim check --min-level:warning <files>`. Fix every warning you introduced.
- How to run them on a single file outside a project:
  - Put a copy of `lints/nim.cfg` named `nim.cfg` next to the file, then `nim check file.nim`.
    Nim reads `nim.cfg` from the file's directory and its parents; there is no option to load a
    configuration file from elsewhere.
  - The file name is the module name, so it must be a Nim identifier (`kv_config.nim`, not
    `kv-config.nim`). Otherwise check a copy under a valid name and say so in your report.
  - If the code has `runnableExamples`, also run `nim doc file.nim`: only `nim doc` compiles and
    runs them (section 10). `nim doc` exits 0 even on markup errors in `##` comments
    (`Error: '**' expected` for a bare `**`): read its output for `Error:` and `Warning:` lines.
  - If the code defines hooks (`=destroy`, `=copy`), also run `nim c file.nim`. `nim check` stops
    before destructor injection, so it exits 0 on a copy that `=copy {.error.}` forbids; only
    `nim c` reports it. To list where a type is copied, add `=copy {.error.}` for a moment and
    read the `nim c` errors. Only routines the program calls are checked, and the build stops at
    the first routine that copies: call every routine from a probe, fix what is reported, and
    rebuild until it is clean.
  - If the code imports C through a `header`, also build a probe that calls every proc that
    calls C, with `nim c`. `nim check` does not run the C compiler, and only the C compiler
    checks the call against the header's prototype (clang rejects a `qsort` comparator that
    takes `void*` instead of `const void*`). `nim c` on the module alone leaves out the procs
    nothing calls, so it checks nothing.
  - `beautifulnim check` prints nothing and exits 0 when it finds nothing; add `--format:json` to
    see each file it parsed.
- Read `details/pitfalls.md` once: code that compiles but does not do what it reads as.
- Use `lints/nim.cfg` (copy the lines into the project's `nim.cfg`): `--styleCheck:usages`,
  `--styleCheck:error`, and the warnings that point at real bugs as errors (`InheritFromException`,
  `UnusedImport`, `StdPrefix`, `CStringConv`, `EnumConv`, `HoleEnumConv`, `UnsafeDefault`,
  `UnsafeSetLen`, `ResultShadowed`, `UseBase`).
- **Fix warnings, do not silence them (BN-04).** No `{.push warnings: off.}`, `{.warning[X]: off.}`
  or `{.hint[X]: off.}` in source and no `--warnings:off` in a project's `nim.cfg`. If a compiler
  bug forces one, scope it to one statement and name the compiler issue in a comment; `beautifulnim check`
  still reports it so a reviewer decides. (`--hints:off` on the command line for quieter test output
  is fine; it changes nothing in the code.)
- Spell every identifier exactly as declared. Nim matches `readAll`, `read_all` and `readall` as the
  same name; `--styleCheck:error` stops the mixture (Status).

## 3. Values, copies and moves (ARC/ORC)
- **Value semantics by default.** `object`, `seq`, `string` and tuples copy on assignment; the
  compiler turns the last use of a value into a move. Write code that lets it: do not read a
  variable again after passing it to a `sink` parameter. This applies to locals inside a routine
  only. A module-level `var` is never moved implicitly, because other code may still read it:
  write `move(x)`, or put the code in a `proc main()`.
- **Parameter modes say ownership.** Plain `T` for reading (the compiler passes large values by
  reference anyway), `sink T` when the callee stores or consumes the value, `var T` only to mutate
  in place, `lent T` as the return type of a getter that hands out a view of a field. Return several
  results as a tuple or object, not through `var` out-parameters (manual).
- **`ref` only when you need reference semantics** (Status): a handle to a resource that must not be
  copied, real shared ownership, linked structures (trees, graphs), or a stable address for foreign
  code. When both forms exist, the value type gets the plain name and the other `FooRef` (NEP1
  gives the plain name to the variety used most; the Status guide always suffixes `Ref`; follow the
  project).
- **Resources and hooks.** A type that owns memory or an operating-system resource decides what
  a copy does (`=copy {.error.}` or a deep `=copy`); `=destroy` is for a raw pointer or OS
  handle, not a `seq` field. Read `details/ownership.md` before writing either.
- Iterate with `items`/`pairs` to read and `mitems`/`mpairs` to change elements in place; neither
  copies the elements. Use `move(x)` or `ensureMove(x)` only where the compiler cannot see that a
  value is no longer used.

## 4. Types and API design

### Naming (NEP1)

| Thing | Style | Example |
|---|---|---|
| Types | PascalCase | `HttpClient`, `ParseError` |
| Procs, vars, fields, params | camelCase | `readAll`, `maxRetries` |
| Constants | camelCase or PascalCase | `defaultPort`, `MaxDepth` |
| Enum values (not `{.pure.}`) | short lowercase prefix + PascalCase | `pcFile`, `pcDir` |
| Exceptions | `…Error` (CatchableError) or `…Defect` | `ConfigError` |

- Acronyms are words: `parseUrl`, `HttpHeader`, not `parseURL` (NEP1). No underscores in Nim names;
  wrappers of C code keep the C name through `importc` (BN-05 allows it there).
- Getters are named `foo`, not `getFoo`; setters are `foo=` (NEP1). Use `getFoo`/`setFoo` only when
  the call is expensive or has side effects (BN-05 reports public `getFoo` at level info).
- Order words subject-verb: `fileExists`, not `existsFile`. The in-place form is the verb, the
  copying form its past participle: `sort`/`sorted`, `reverse`/`reversed`.
- Standard vocabulary: `initFoo` constructs a value, `newFoo` a `ref`; `len`, `add`, `contains`
  (returns bool), `find` (returns an index), `del` (fast, unordered) vs `delete` (keeps order),
  `incl`/`excl` for sets, `items`/`pairs` for iterators.
- Constructors: NEP1's `initFoo`/`newFoo` is the default. The Status guide's `Foo.init(...)` and
  `Foo.new(...)` are equally clear; follow what the project already does and do not mix the two.
- No `Manager`, `Helper`, `Util` or `Impl` names; name the thing by what it is.

### Model the domain with types

- **`distinct` for units and IDs**, with `{.borrow.}` for the operations that make sense:

```nim
type Meters = distinct float

proc `+`(a, b: Meters): Meters {.borrow.}
proc `<`(a, b: Meters): bool {.borrow.}
proc `$`(m: Meters): string = $float(m) & " m"

let total = Meters(1.5) + Meters(2.0)
doAssert Meters(3.0) < total
echo total
```

- **No `bool` parameters in public APIs (BN-02).** `open(path, true)` says nothing at the call site.
  Use an enum, or two procs:

```nim bad
proc connect*(host: string; secure: bool) = discard
connect("example.com", true)
```

```nim
type Transport* = enum
  plain, tls

proc connect*(host: string; transport: Transport) =
  echo host, " over ", transport

connect("example.com", tls)
```

- **Independent flags are a `set[Enum]`** (a bit set, no extra library):
  `open(path, {fmRead, fmCreate})`, not three booleans. A C flag word is not a `set`
  (details/ffi.md).
- **Absence is `Option[T]`**, never a sentinel (`-1`, `""`, `nil`). A field that only exists for
  one kind of value belongs in an **object variant**:

```nim
import std/options

type
  ShapeKind = enum
    skCircle, skRect
  Shape = object
    case kind: ShapeKind
    of skCircle:
      radius: float
    of skRect:
      width, height: float

func area(s: Shape): float =
  case s.kind
  of skCircle: 3.14159 * s.radius * s.radius
  of skRect: s.width * s.height

func findShape(shapes: openArray[Shape]; kind: ShapeKind): Option[Shape] =
  for s in shapes:
    if s.kind == kind: return some(s)
  none(Shape)

let shapes = [Shape(kind: skCircle, radius: 1.0), Shape(kind: skRect, width: 2, height: 3)]
let rect = findShape(shapes, skRect)
if rect.isSome:
  echo area(rect.get)
```

  Write `case` over an enum **without `else`**, so adding a value makes every unhandled `case` a
  compile error.
- **Validate once.** A constructor that checks its input returns `Option[T]` or raises a specific
  `CatchableError`; the rest of the code trusts the type. Use `range[a..b]`, `Natural` and
  `Positive` where a bound is part of the meaning; conversions into them are checked at run time.
- **Prefer a valid zero value** (Status): `default(T)` should be usable. When it cannot be, mark the
  type `{.requiresInit.}` so the compiler refuses uninitialised variables.
- Binary data is `seq[byte]` / `openArray[byte]`, not `string` (Status).

### Visibility and evolution

- Export (`*`) only what is part of the API, field by field. Every exported symbol is a promise and
  takes part in overload resolution in every importing module (Status).
- Take `openArray[T]` rather than `seq[T]` for read-only sequences, so arrays and slices work too
  (Status). Take `string` for text you keep and `openArray[char]` only for hot read-only paths.
- Keep the subject first so method call syntax reads well: `buf.add(x)`, `conn.send(msg)`.
- Do not export a type from a dependency in your API without re-exporting its module (`export`);
  otherwise callers need an import they cannot guess (Status).

### Procs, templates, macros, converters, methods

- **`func` when there are no side effects** (it is `proc {.noSideEffect.}`); the compiler then
  checks the claim (Status prefers `func`; NEP1 predates it).
- **proc > template > macro** (NEP1, Status, the manual). See *Templates and macros* below.
- **No converters (BN-03).** They make conversions invisible and cause ambiguous overloads; call an
  explicit `toFoo`.
- **Methods rarely (BN-07).** Dynamic dispatch needs `ref` types and whole-program knowledge.
  A closed set of types is an object variant; an open set can be an object holding closures.
  When you do use `method`, mark the root `{.base.}` (`UseBase` is an error in `lints/nim.cfg`).
- **Generics before concepts.** Constrain with type classes (`T: SomeInteger`); concepts are for
  when that is not enough.
- **Annotate proc types**: `proc (x: int) {.raises: [], gcsafe.}`. Without it the compiler assumes
  the callback may raise `Exception` and touch globals, and that spreads to every caller (Status).

### Templates and macros

Use the least powerful tool that works: a proc, then a generic proc, then a template, then a
macro. Read `details/templates-and-macros.md` before writing a template or a macro: hygiene
(BN-08), building trees rather than strings (BN-09), evaluating each argument once (BN-10), and
how to test them.

### Refactoring someone else's code

- Fix every smell the request is about: `except: discard`, `bool` parameters, converters, `getFoo`
  getters, `ref object` without a reason, `result` assigned in every branch, `include`, string-typed
  binary data, missing `raises`, warnings switched off.
- Keep public behaviour identical unless changing it is the point. Turning a crash into a raised
  `CatchableError` or an `Option` is the desired kind of change; show every signature change before
  and after with the reason.
- If there are no tests, write tests that pin the current behaviour first, quirks included, and
  list the quirks you kept.

## 5. Errors

| Situation | Use |
|---|---|
| A value may legitimately be absent | `Option[T]` |
| A value is present but invalid (a stored `"abc"` read as an integer) | raise; keep `Option` for absence only |
| The caller can recover (bad input, I/O, network) | raise a `CatchableError` subtype, or return a result value (the `results` package) if the project uses it |
| A bug, a broken invariant | `doAssert` / `raiseAssert` (a `Defect`) |

- **Annotate effects on every exported routine** — `proc`, `func`, `iterator`, `method`, getters
  included: `{.raises: [].}` when nothing escapes, `{.raises: [IOError, ParseError].}` otherwise.
  The compiler checks the list, so it is documentation that cannot go stale. Simplest: put
  `{.push raises: [].}` at the top of the module and add a `raises` list only where an exception
  escapes. The annotation exposes the usual leaks; handle them where they occur:
  - `t[key]` on a `Table` raises `KeyError`: use `t.getOrDefault(key)` after `key in t`.
  - `parseInt` and other parsers raise `ValueError`: catch it and convert, as in the example below.
- **`raises` lists `CatchableError`s only.** `Defect`s (`IndexDefect`, `AssertionDefect`,
  `OverflowDefect`, …) are not tracked: a proc marked `{.raises: [].}` may still raise one, and
  listing one only earns the hint "cannot raise" (`XCannotRaiseY`). Name the Defects a proc raises
  on misuse in its `##` comment. Templates and macros have no effects of their own and take no
  `raises`: their expansion is checked against the routine that calls them.
- Integer overflow raises `OverflowDefect`. A sum of amounts that come from outside checks
  before it adds (`if b > 0 and a > high(int64) - b: raise ...`), or the doc comment states the
  bound the inputs keep.
- **Never swallow an error (BN-01).** An `except` whose body is only `discard` hides failures.
  Propagate it, convert it to a value, or log what failed and why. Catch the narrowest type.
- **Never `except Exception:`** — it also catches `Defect`s, which are bugs. The compiler warns
  (`BareExcept`), but `lints/nim.cfg` cannot make that an error because `std/unittest` trips it.
  In Nim 2 a bare `except:` catches `CatchableError` only; still name the type.
- **Exception types inherit from `CatchableError` or a stdlib subtype (`ValueError`, `IOError`,
  `OSError`), or from `Defect`** — never from `Exception` (NEP1; the compiler warns
  `InheritFromException`). Name them `…Error`/`…Defect`.
- Messages carry the values: `raise newException(ParseError, "line " & $n & ": expected ':'")`.
- `assert` disappears with `-d:danger`; `doAssert` stays. Use `doAssert` for checks that protect
  memory, security or data, `assert` for expensive internal checks.
- Do not call `get` on an `Option` you have not checked; use `isSome`, `get(opt, default)` or `case`.
- `defer` is fine for one-off cleanup; a type that always needs cleanup gets a destructor.

```nim
import std/strutils

type ConfigError* = object of ValueError

proc parsePort*(s: string): int {.raises: [ConfigError].} =
  ## Parses a TCP port number, 1..65535. The cause of a failure stays attached (`parent`).
  let n =
    try: parseInt(s)
    except ValueError as e: raise newException(ConfigError, "not a number: " & s.escape, e)
  if n notin 1 .. 65535:
    raise newException(ConfigError, "port out of range: " & $n)
  n

doAssert parsePort("8080") == 8080
```

## 6. Everyday idioms

- `let` by default, `var` when the value changes, `const` when it is known at compile time; group
  related constants in one `const` block (NEP1, Status).
- **Return with expressions.** `if` and `case` are expressions; a proc whose body is one expression
  returns it, and the compiler then rejects a branch that forgets the value. Use `result` for
  accumulation (building a `seq` or `string` in a loop) and `return` for early exits. (NEP1 says
  use `result` whenever possible; the Status guide says avoid it. We side with Status for
  branching code because the compiler checks every branch, and with NEP1 for accumulation.)

```nim
func classify(n: int): string =
  if n < 0: "negative"
  elif n == 0: "zero"
  else: "positive"

func squares(n: Natural): seq[int] =
  for i in 0 ..< n:
    result.add i * i

doAssert classify(-3) == "negative"
doAssert squares(3) == @[0, 1, 4]
```

- Ranges without spaces: `a..b`, `a..<b`, `s[^1]` (NEP1).
- Strings: `&` for a few pieces, `fmt"…"`/`&"…"` (std/strformat) for templates, `add` in loops,
  `join` for lists. Build large strings with `newStringOfCap`.
- `sequtils` (`mapIt`, `filterIt`, `allIt`) for short pipelines; a `for` loop when the body grows.
- Imports: `std/` prefix for the standard library (`StdPrefix` is an error in `lints/nim.cfg`),
  grouped std, then packages, then local `./` modules (Status). Import what you use.
- **No `include` (BN-06)**: it pastes source text, so nothing says where a name comes from. Import
  the module; use `include` only for generated code or when a module must be split for the
  compiler's sake, with a comment saying so.
- Named constants instead of magic numbers, with a comment on where the value comes from.
- `echo` is for command-line output; libraries log through `std/logging` or the project's logger.
  When the specification itself requires a write to stderr, write to `stderr`: the rule is about
  diagnostics nobody specified.
- Two-space indent, no tabs; lines up to 80 characters (NEP1; the Status guide uses `nph`, which
  wraps at 88 — follow the project's formatter; with none, 80). Do not align with extra spaces.

## 7. Concurrency and async

Move data between threads instead of sharing it; a thread proc is `gcsafe`; use one async runtime
per program; libraries do not start threads or run the event loop. Read `details/concurrency.md`
before writing threads, locks, channels or async code.

## 8. Unsafe code and FFI

- The unsafe features are `cast`, `ptr`, `addr`, `copyMem`/`moveMem`, `UncheckedArray`, `{.emit.}`,
  `{.cast(...).}` and turning checks off (`{.push rangeChecks: off.}`, `-d:danger`). Use them only
  for FFI, a measured hot path, or what safe code cannot express. Keep each use in a small proc with
  a safe signature and a comment saying why it is sound.
- Prefer `openArray`, `toOpenArray(s, a, b)` and slices to pointer arithmetic.
- `addr s[i]` on a `seq` or `string` is valid only until the next operation that may reallocate
  it: `add`, `setLen`, `insert`, `delete`, or a move of the whole value. Hold the index instead,
  or finish with the pointer before you change the length.
- Turn a check off only around measured hot code, locally, with the measurement in a comment.
- Run the checks `details/ffi.md` lists.

## 9. Packages and modules

- One nimble package per repository: `src/<pkg>.nim` as the entry that re-exports
  `src/<pkg>/*.nim`; internals in `src/<pkg>/private/`. `nimble test` runs `tests/t*.nim`.
- `requires` with bounds (`"foo >= 1.2.0 & < 2.0.0"`); applications commit a lock file
  (`nimble lock`).
- No side effects at import time: no I/O or threads started in top-level statements of a library.
- Re-export a module whose types appear in your public procs (`export foo`) (Status).
- Compile-time options are `-d:name` flags read with `when defined(name)`; document every one.
- State the Nim version (`requires "nim >= 2.0.0"`) and build with `--mm:orc` (the default).

## 10. Documentation and comments

- `##` doc comments on every exported symbol; the first sentence is a one-line summary. A module
  starts with a `##` paragraph saying what it is for.
- Put examples in `runnableExamples:` blocks; `nim doc` compiles and runs them, so they stay true.
  The block goes in the routine's body after the `##` lines, never inside the doc comment.
  Doc comments are RST: a bare `**` (as in `2**31`) is a markup error; write `2^31` or put
  code in double backquotes.
  Every public template and macro has one, and so does every exported proc or iterator that
  raises, takes a callback, or behaves specially at an edge (empty input, a bound). Plain getters
  and one-line wrappers need none.
  A block sees the module's exported symbols but **not the module's imports**: import what the
  example uses (`std/options`, `std/tables`) inside the block, operators included (`in` on
  strings comes from `std/strutils`), as below. When `nim doc` fails on an
  example it prints the whole command; the error is in the lines before it.
- Fields and enum values take their `##` on the same line, after the declaration.
- Document what the signature cannot say: preconditions, complexity, ownership, side effects.
  `raises` and `gcsafe` are in the signature already.
- `#` comments explain why, not what. `TODO:` with an issue link. No change logs in comments.

```nim
import std/options

type Parity* = enum
  pEven ## divisible by two
  pOdd  ## not divisible by two

func firstOf*(xs: openArray[int]; parity: Parity): Option[int] {.raises: [].} =
  ## The first number in `xs` with the given parity, if any.
  runnableExamples:
    import std/options # the block does not see the module's imports
    doAssert firstOf([1, 4, 6], pEven) == some(4)
    doAssert firstOf([2, 4], pOdd).isNone
  for x in xs:
    if (x mod 2 == 0) == (parity == pEven): return some(x)
  none(int)
```

## 11. Tests
- `std/unittest` with `suite`/`test`, files under `tests/` named `t*.nim` (or the project's task).
  `check` prints the values of both sides when it fails.
- Name tests by behaviour ("Given…, when…, then…"), test properties (round-trip, idempotence,
  ordering) rather than restating constants, and write the failing test before fixing a bug.
- Inject time, randomness and I/O as parameters (proc types or objects of closures), so tests do
  not touch the clock, the network or the disk unless they mean to.
- Outside a project there is no test task: run a test file with `nim c -r tests/tfoo.nim`; it
  imports the module by relative path (`import ../foo`). A directory name that is not a Nim
  identifier goes in quotes: `import "../check-project/foo"`.
- `runnableExamples` are tests too, and documentation first: a task that asks for no tests
  still gets them, on every public symbol that section 10 says needs one. Show a runtime error with
  `doAssertRaises(IndexDefect): discard b[9]`; `doAssert not compiles(...)` is only for what
  must not compile.
- Read `details/testing.md` when the code parses untrusted input, owns memory or calls C, or
  must fail to compile in some use.

## 12. Performance, in order

1. Make it correct and clear; measure with `-d:release` and a profiler before changing anything.
2. Preallocate: `newSeqOfCap`, `newStringOfCap`, `setLen`, `initTable(n)`.
3. Avoid copies: `sink`/`lent`, `openArray` parameters, `move` where the compiler cannot see it.
4. Avoid allocations: value objects over `ref`, reuse buffers the caller passes in.
5. After measuring, a program with no cycles may switch to `--mm:arc` (orc stays the default),
   and link-time optimisation (`--passC:-flto
   --passL:-flto`) rather than `{.inline.}` everywhere (Status).
6. Never ship `-d:danger` as the default build; it removes the checks that turn bugs into errors.

## 13. Final checklist

- `nim check` clean with `lints/nim.cfg`; tests pass; `beautifulnim check` reports nothing at level warning
  or above, or each report has a reason.
- Every exported proc, func and iterator has `raises` (section 0 when the task's signature lacks it); no `except Exception:`, no `except` that only discards.
- No warnings switched off; no `converter`; no `include`; `method` only for open hierarchies.
- No public `bool` parameters; enums, `distinct`, `range`, `Option` and object variants carry the
  meaning.
- `ref` only with a reason; resource types have `=destroy`, `=copy {.error.}` if unique, and an
  explicit `close`.
- NEP1 names; identifiers spelled as declared.
- `##` docs with a summary line on every exported symbol; examples in `runnableExamples`.
- Every `cast`, `ptr`, `addr` and disabled check has a comment saying why it is sound.
- Templates and macros only where a proc cannot do it; hygienic, each argument evaluated once
  unless the doc comment says otherwise, trees built with `genAst`/`quote`, misuse reported at the
  caller's node.

## References

- `references/nep1.md` — naming, layout and coding conventions of the standard library.
- `references/nim-manual.md` — effects (`raises`, `gcsafe`, `func`), `distinct`, `ref`/`ptr`,
  methods, converters, exceptions.
- `references/macros.md` — templates and macros: the manual's rules, and the Lisp lessons (On Lisp,
  Google's Common Lisp guide) mapped to Nim.
- `references/destructors.md` — hooks, move semantics, `sink`/`lent`, `cursor`.
- `references/status-style-guide.md` — production practices (errors, `ref object`, `result`,
  `func`, imports, formatting).
- Machine checks: `beautifulnim check` (see the repository README); compiler settings:
  `lints/nim.cfg`.
