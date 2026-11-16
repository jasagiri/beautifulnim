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
reported by `beautifulnim check` (the CLI in this repository); rules the compiler checks are switched on in `lints/nim.cfg`.

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
    runs them (section 10).
  - `beautifulnim check` prints nothing and exits 0 when it finds nothing; add `--format:json` to
    see each file it parsed.
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
  variable again after passing it to a `sink` parameter.
- **Parameter modes say ownership.** Plain `T` for reading (the compiler passes large values by
  reference anyway), `sink T` when the callee stores or consumes the value, `var T` only to mutate
  in place, `lent T` as the return type of a getter that hands out a view of a field. Return several
  results as a tuple or object, not through `var` out-parameters (manual).
- **`ref` only when you need reference semantics** (Status): a handle to a resource that must not be
  copied, real shared ownership, linked structures (trees, graphs), or a stable address for foreign
  code. When both forms exist, the value type gets the plain name and the other `FooRef` (NEP1
  gives the plain name to the variety used most; the Status guide always suffixes `Ref`; follow the
  project).
- **Resources get a destructor, not a finalizer.** Write `=destroy`, decide what a copy means, and
  reset in `=wasMoved`. Destructors must not fail or raise; give the type an explicit `close` that
  reports errors, and let `=destroy` be the best-effort fallback. Finalizers (`new(x, finalizer)`)
  are not deterministic (Status).
- **A type with `=destroy` must say what a copy does.** Without `=copy` the compiler copies the
  fields bit by bit, so two values free the same memory: a double free the first time anyone
  passes the value to a non-`sink` parameter or adds it to a `seq`. Choose one:
  - `=copy {.error.}` when the type owns something unique (a file, a socket, a lock) or a copy
    would be a hidden allocation on a hot path. `=dup` then becomes unavailable as well; it needs no
    hook of its own.
  - a deep `=copy` that allocates and copies, when the type is a general container whose users
    expect value semantics, as `seq` does.

```nim
import std/[oserrors, posix]

type
  Fd = object
    ## An open file descriptor. Move-only: a copy would close it twice.
    raw: cint

proc `=destroy`(f: Fd) =
  if f.raw >= 0:
    # Best effort: a caller that cares about the error calls close first.
    discard posix.close(f.raw)

proc `=wasMoved`(f: var Fd) = f.raw = -1
proc `=copy`(dst: var Fd; src: Fd) {.error.}

proc close(f: var Fd) {.raises: [OSError].} =
  ## Closes now and reports failure; the destructor then has nothing left to do.
  if f.raw >= 0:
    let rc = posix.close(f.raw)
    f.raw = -1
    if rc != 0: raiseOSError(osLastError())

proc openFd(path: string): Fd {.raises: [OSError].} =
  let raw = posix.open(path.cstring, O_RDONLY)
  if raw < 0: raiseOSError(osLastError(), path)
  Fd(raw: raw)

var f = openFd("/dev/null")
f.close()
```

- `{.cursor.}` marks a non-owning `ref` (a parent pointer) to break a cycle without the cycle
  collector. It is a raw pointer with no checks: the target must outlive it.
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
  `open(path, {fmRead, fmCreate})`, not three booleans.
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

A template pastes syntax trees at the call site; a macro is a proc the compiler runs on syntax
trees. Both are expanded into the caller's code, which is where their power and their bugs come
from. Lisp has lived with this for decades, and its lessons carry over almost unchanged
(`references/macros.md` maps them to Nim).

**Use the least powerful tool that works** (the manual's style note): a proc, then a generic
proc, then a template, then a macro. Speed is not a reason to climb: mark a small proc
`{.inline.}` instead (Google's Lisp guide: do not use macros for performance). Climb only for what a
proc cannot do (On Lisp, ch. 8):

- **Control evaluation**: run an argument lazily (only when logging is on), repeatedly (a body in
  a loop) or never (`astToStr`, `compiles`). A proc evaluates every argument exactly once, first.
- **Bind names the caller uses**: `withFile(f, …)` declares `f`; `mapIt` provides `it`.
- **Look inside an argument's syntax** (transformation): only a macro can see that an argument is
  `a == b` and report both sides. A template cannot take its argument apart.
- **Compute at compile time** what `const` and a proc called in a `const` cannot.

When you do climb, these hold:

1. **Stay hygienic (BN-08).** Templates are hygienic by default: a `let` or `var` inside one gets a
   fresh name and cannot clash with the caller's. Keep it that way. A name the caller must see
   comes in as a parameter or is marked `{.inject.}`, and the doc comment lists it. `{.dirty.}`
   switches hygiene off for every name in the template; keep it only with a comment saying why.
   Never read a caller's variable that is not a parameter: On Lisp calls such capture "a source of
   contagion" and notes that it usually happens by mistake.
2. **Evaluate each argument once, in order (BN-10).** A template pastes the argument's *tree* at
   every use, typed parameters included, so `sq(next())` with `x * x` in the body calls `next`
   twice. Bind each argument with `let` in the order the parameters appear, then use the binding.
   The exceptions are the arguments the template exists to repeat or skip (a loop body, a lazily
   built message). Say so in the doc comment, so callers know.
3. **Build trees, not strings (BN-09).** In a macro, build code with `genAst` (std/genasts) or
   `quote do`. `parseStmt`/`parseExpr` on assembled text loses hygiene and the caller's line
   information. It also turns whatever reaches the string into code.
4. **A macro processes syntax; the work goes in procs.** Keep the expansion small. Have it call
   an ordinary proc that holds the logic, so that the logic is tested as a proc (Google's Lisp
   guide calls this "call-with style").
5. **Check the input's shape and report at the caller.** Before building anything, check the kind
   of each node (`expectKind`, `expectLen`, or an `if` with `error(msg, node)`). Then a misuse is one
   clear error on the caller's line, not a confusing one inside the expansion.
6. **`typed` before `untyped`.** Give a parameter a real type when it is a value: overloads resolve
   and type errors appear before expansion. Use `untyped` only for a name to bind, a body, or syntax
   to transform.
7. **Make it readable from outside.** Every public template and macro has a `##` comment that says
   what it expands to in words, which names it injects, and how often each argument is evaluated,
   plus `runnableExamples`. Do not generate the public API with macros: it cannot be found by
   reading or documented (Status). Avoid macros that write macros (Google's Lisp guide).
8. **Say what control flow does inside a body.** A body parameter placed inside the template's
   own `while` or `for` captures the caller's `break` and `continue`: they leave your loop, not
   theirs, and nothing warns. `return` leaves the caller's proc. State in the doc comment which of
   these work. If `break` must reach the caller's loop, use a loop variable instead of a loop
   around the body.
9. **Keep helpers private.** The proc that an expansion calls (rule 4) can stay unexported:
   templates and `genAst`/`quote` bind the symbols visible where they are defined. Exporting it
   would only add to the caller's namespace. Test the expansion from another module to be sure.
10. **Test the behaviour and the misuse.** Test what the expansion does, as you would a proc. Test
   rejected input with `doAssert not compiles(...)`. To see an expansion, use `expandMacros` or
   `echo result.repr` while writing the macro, and remove it before you hand the code back.

```nim bad
template sq*(x: int): int = x * x # sq(next()) calls next twice (BN-10); a proc would do
```

```nim
func sq*(x: int): int {.inline.} = x * x # a proc evaluates x once; inline keeps it fast

const debugLog {.booldefine.} = false

template debug*(msg: string) =
  ## Writes `msg` to stderr when compiled with `-d:debugLog`. `msg` is evaluated only then,
  ## so building it costs nothing in a normal build.
  when debugLog:
    stderr.writeLine msg
```

A macro that needs to see inside its argument checks the argument's shape, evaluates each operand
once, and builds the result with `genAst`:

```nim
import std/[macros, genasts]

macro expect*(cond: untyped): untyped =
  ## Like `doAssert`, but a failed comparison shows both operands. Each operand is evaluated once,
  ## left to right; the names `l` and `r` are hygienic and cannot clash with the caller's.
  runnableExamples:
    let a = 2
    expect a + 1 == 3
    doAssert not compiles(expect true)
  if cond.kind != nnkInfix or cond.len != 3:
    error("expect needs a comparison such as `a == b`", cond)
  let text = cond.repr
  result = genAst(op = cond[0], lhs = cond[1], rhs = cond[2], text):
    let l = lhs
    let r = rhs
    if not op(l, r):
      raiseAssert text & ": left is " & $l & ", right is " & $r
```

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
- Two-space indent, no tabs; lines up to 80 characters (NEP1; the Status guide uses `nph`, which
  wraps at 88 — follow the project's formatter). Do not align with extra spaces.

## 7. Concurrency and async

- Threads are on by default in Nim 2. Move data between threads instead of sharing it:
  `Isolated[T]` (std/isolation) proves a value has no other references; channels pass ownership.
- A thread proc must be `gcsafe`: no access to globals holding `string`, `seq`, `ref` or closures.
  Do not silence that with `{.cast(gcsafe).}`; restructure, or explain in a comment why the access
  is safe and how it is synchronised.
- Shared state: one `Lock` per invariant, fields marked `{.guard: lock.}` so the compiler enforces
  `withLock`, short critical sections, and no callbacks or I/O while holding a lock.
- Async: use one runtime per program — `std/asyncdispatch` or `chronos` — and follow the project.
  `await` every future or handle it; `asyncCheck` turns a failure into a crash of the dispatcher.
  CPU-bound work blocks the event loop; give it a thread pool.
- Libraries do not start threads or run the event loop; they take what they need as parameters.

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
- FFI: `importc` with a `header`, C types (`cint`, `csize_t`, `cstring`), and a Nim wrapper that
  converts at the boundary. A `cstring` does not own its bytes: keep the Nim `string` alive while
  C uses it (`CStringConv` is an error in `lints/nim.cfg`). Free memory with the allocator that
  allocated it. Wrap an owning C pointer in an object with `=destroy`. Turn `NULL` into `Option` or
  a raised error. Callbacks passed to C are `{.cdecl, raises: [].}`: an exception must not unwind
  through C frames.
- Use `distinct` for handles from C so they cannot be mixed up.
- Memory you own directly: allocate in one constructor
  (`cast[ptr UncheckedArray[T]](alloc0(n * sizeof(T)))`, with the comment), free it in `=destroy`,
  and decide copies as in section 3. `UncheckedArray` has no bounds checks, so every exported
  accessor checks the index against the length itself and raises `IndexDefect` (an `if`, not
  `doAssert`, so that `-d:danger` keeps it). Use `allocShared0`/`deallocShared` only if the memory
  crosses threads.

```nim
proc cStrlen(s: cstring): csize_t {.importc: "strlen", header: "<string.h>".}

proc byteLen*(s: string): int =
  ## Length up to the first NUL, measured by C.
  int(cStrlen(s.cstring))

doAssert byteLen("abc") == 3
```

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
  A block sees the module's exported symbols but **not the module's imports**: import what the
  example uses (`std/options`, `std/tables`) inside the block, as below. When `nim doc` fails on an
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
- Fuzz parsers of untrusted input; run tests under sanitizers
  (`-d:useMalloc --passC:-fsanitize=address --passL:-fsanitize=address --debugger:native`).
  Where the sanitizer cannot run, test memory ownership two other ways: build with `-d:useMalloc`
  so the platform allocator aborts on a double free (on macOS, also run with `MallocScribble=1`).
  Then, with the default allocator, compare `getOccupiedMem()` before and after a loop of
  create, move and destroy, which shows a leak.
- Test what must not compile. `doAssert not compiles(expr)` works for type errors and a macro's
  `error`, but not for a forbidden copy: `=copy {.error.}` is reported after `compiles` has
  answered. Put the copy in its own file and expect `nim c` to fail.
- `runnableExamples` are tests too.

## 12. Performance, in order

1. Make it correct and clear; measure with `-d:release` and a profiler before changing anything.
2. Preallocate: `newSeqOfCap`, `newStringOfCap`, `setLen`, `initTable(n)`.
3. Avoid copies: `sink`/`lent`, `openArray` parameters, `move` where the compiler cannot see it.
4. Avoid allocations: value objects over `ref`, reuse buffers the caller passes in.
5. Use `--mm:arc` when the program has no cycles, and link-time optimisation (`--passC:-flto
   --passL:-flto`) rather than `{.inline.}` everywhere (Status).
6. Never ship `-d:danger` as the default build; it removes the checks that turn bugs into errors.

## 13. Final checklist

- `nim check` clean with `lints/nim.cfg`; tests pass; `beautifulnim check` reports nothing at level warning
  or above, or each report has a reason.
- Every exported proc has `raises`; no `except Exception:`, no `except` that only discards.
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
