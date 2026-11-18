# Code that compiles but reads wrong

Part of nim-best-practices section 2. Read it once. Each item is accepted by Nim 2.4 without a
warning, or rejected with an error that does not name the cause.

- A space before `(` turns a call into a command call. `f (1, 2)` passes the tuple `(1, 2)` as
  one argument; `f(1, 2)` passes two.
- A command call takes the whole expression after it: `doAssert f 1 == 1` asserts
  `f(1 == 1)`. Write calls inside assertions with parentheses: `doAssert f(1) == 1`.
- In method-call syntax, `x.p[T]()` reads `[T]` as an index, and the error is "cannot
  instantiate". Give the generic parameter as `x.p[:T]()`.
- `except` branches are tried in order, so a branch for a subtype placed after a branch for its
  parent never runs, and the compiler does not warn. Order them from the most specific type to the
  most general.
- `nim doc` drops a `##` line that stands alone inside a `type` section, and adds a `##` line
  between two module-level declarations to the module's description. A symbol's `##` goes on
  its declaration line or the indented lines right under it (for a routine, the first lines of
  its body).

```nim
type
  ConfigError* = object of CatchableError
  MissingKey* = object of ConfigError

proc describe*(e: ref ConfigError): string =
  ## The most specific branch comes first.
  try:
    raise e
  except MissingKey:
    "missing key"
  except ConfigError:
    "config error"

doAssert describe(newException(MissingKey, "port")) == "missing key"
doAssert describe(newException(ConfigError, "port")) == "config error"
```

```nim bad
doAssert len "abc" == 3 # parsed as len("abc" == 3): a type error, not a length check
```
