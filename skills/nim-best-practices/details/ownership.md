# Resources, hooks and owned memory

Part of nim-best-practices section 3. Read it before writing `=destroy`, `=copy`, `=wasMoved`,
`{.cursor.}`, or a type that owns memory or an operating-system resource.

- **Resources get a destructor, not a finalizer.** Write `=destroy`, decide what a copy means, and
  reset in `=wasMoved`. Destructors must not fail or raise. When releasing can fail (a file, a
  socket), give the type an explicit `close` that reports errors, and let `=destroy` be the
  best-effort fallback; memory alone needs no `close`. Finalizers (`new(x, finalizer)`)
  are not deterministic (Status).
- **A type with `=destroy` must say what a copy does.** Without `=copy` the compiler copies the
  fields bit by bit, so two values free the same memory: a double free the first time a copy is
  made. Passing the value to a plain parameter only borrows it; a copy happens when a value that
  is still used afterwards is stored (added to a `seq`, assigned to a variable or a field).
  Choose one:
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
- Memory you own directly: allocate in one constructor
  (`cast[ptr UncheckedArray[T]](alloc0(n * sizeof(T)))`, with the comment), free it in `=destroy`,
  and decide copies as in section 3. Keep the zero value valid (section 4): `default(T)` holds a
  `nil` pointer, so `=destroy` frees only when the pointer is not `nil`. `UncheckedArray` has no bounds checks, so every exported
  accessor checks the index against the length itself and raises `IndexDefect` with an `if`, the
  same defect built-in indexing raises (`doAssert` would raise `AssertionDefect`; both survive
  `-d:danger`). Use `allocShared0`/`deallocShared` only if the memory
  crosses threads.
