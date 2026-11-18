# FFI and unsafe code

Part of nim-best-practices section 8. Read it before writing `importc`, a C callback, `cast`,
`ptr`, `addr` or `UncheckedArray`.

- Prefer `openArray`, `toOpenArray(s, a, b)` and slices to pointer arithmetic.
- `addr s[i]` on a `seq` or `string` is valid only until the next operation that may reallocate
  it: `add`, `setLen`, `insert`, `delete`, or a move of the whole value. Hold the index instead,
  or finish with the pointer before you change the length.
- FFI: `importc` with a `header`, C types (`cint`, `csize_t`, `cstring`), and a Nim wrapper that
  converts at the boundary. A `cstring` does not own its bytes: keep the Nim `string` alive while
  C uses it (`CStringConv` is an error in `lints/nim.cfg`). Free memory with the allocator that
  allocated it. Wrap an owning C pointer in an object with `=destroy`. Turn `NULL` into `Option` or
  a raised error. Callbacks passed to C are `{.cdecl, raises: [].}`: an exception must not unwind
  through C frames.
- A C callback that calls a Nim closure catches what the closure raises, stores it, and the
  wrapper raises it again after the C call returns. Give the closure's type its raises list
  (`proc (x, y: int): int {.raises: [CatchableError].}`), even when the task writes the parameter
  type without it: under `{.push raises: [].}` a proc type without one also means `raises: []`,
  and a closure that raises no longer fits (section 0 allows adding the list to the task's
  signature); name it in your notes. Catch `CatchableError` only; a `Defect` is a bug to fix, not an
  error to carry across C. Build such code with `--panics:on`, so a Defect ends the program
  where it happens instead of unwinding through C: pass it on the command line
  (`nim c --panics:on`) for the program and its probes, and leave the copied `lints/nim.cfg` as
  it is (a project puts it in its own `nim.cfg`). A library cannot set its callers' flags: its
  doc comment says that the callback must not raise a Defect unless the program uses
  `--panics:on`.
- A `{.threadvar.}` may hold refs and closures, and a `gcsafe` proc may read it. Calling the
  closure from a `gcsafe` proc needs `gcsafe` in the closure's type. When the C API has
  no context argument (`qsort`), keep the context in a `{.threadvar.}`: save the old value, set
  it, call C, then restore the old value, so a nested call from inside the callback works.
- A C parameter of type `const T*` needs a type that prints as such:
  `type ConstPtr {.importc: "const void*", nodecl.} = pointer`.
- An opaque C struct, or one whose fields you declare only in part, takes `incompleteStruct`
  with `importc` and `header`: Nim then takes the size from C, and `sizeof` at compile time is an
  error. A struct that a C function takes or returns by value takes `bycopy` (on the type or on
  the parameter).
- Bind a proc either through a `header` (the C compiler sees the prototype and the linker finds
  the symbol) or through `dynlib` (the symbol is loaded at run time), not both: given both,
  Nim 2.4 writes an `#include` of the library's file name and the C build fails.
- When the C API takes a context pointer (`void* userdata`) next to the callback, pass the
  closure through it. Keep the closure in a `ref object`, pin it with `GC_ref` while C may call
  back, and give C a `{.cdecl, raises: [].}` trampoline that turns the pointer back into the `ref`
  (`cast[Ctx](ud)`, the sanctioned cast) and calls the closure; `GC_unref` after the last
  callback. `rawProc` and `rawEnv` split a closure into its two pointers, but the proc part uses
  Nim's calling convention with the environment as an extra last argument, so it fits only a C
  signature made for it; the trampoline fits any.
- When C returns `NULL` for an allocation (`strdup`, `malloc`), raise `OutOfMemDefect`, as
  Nim's own allocator does: `raise newException(OutOfMemDefect, "strdup returned NULL")`
  (`OutOfMemError` is deprecated, and `raiseOutOfMem` is not public).
- Use `distinct` for handles from C so they cannot be mixed up.
- A C flag word (`O_CREAT | O_APPEND`) stays a C integer in the binding, built from the values
  the header defines. A `set[Enum]` is not that integer: its size depends on how many values
  the enum has (1 byte up to 8, 2 up to 16, 4 up to 32), and its bit `i` is the enum's ordinal
  `i`, not the C mask. Offer `set[Enum]` in the Nim API and convert in the wrapper, with no
  `cast`:
- `ptr T` does not index; `ptr UncheckedArray[T]` does. The standard library has no
  pointer-arithmetic module (there is no `std/ptrmath`), and no cast-free way to turn the result
  of `alloc0`, or a pointer C hands you, into an indexable pointer: that one `cast` is the
  sanctioned form, and so is reading the value a C callback's `const void*` points to
  (`cast[ptr int](a)[]`). The exception is a NUL-terminated C string: `for c in mitems(s)` on a
  `var cstring` writes its bytes with no cast (declare the copy with `var`, not `let`). If you only need
  a growable buffer, a `seq[T]` needs no unsafe code at all; use raw memory only when the task
  requires it.

```nim
proc cStrlen(s: cstring): csize_t {.importc: "strlen", header: "<string.h>".}

proc byteLen*(s: string): int =
  ## Length up to the first NUL, measured by C.
  int(cStrlen(s.cstring))

doAssert byteLen("abc") == 3
```

```nim
let
  cCreat {.importc: "O_CREAT", header: "<fcntl.h>".}: cint
  cAppend {.importc: "O_APPEND", header: "<fcntl.h>".}: cint

type OpenFlag* = enum
  ofCreate, ofAppend

proc toCFlags*(flags: set[OpenFlag]): cint =
  ## The C flag word for `flags`, from the header's own values.
  for f in flags:
    result = result or (case f
      of ofCreate: cCreat
      of ofAppend: cAppend)

doAssert toCFlags({}) == 0
doAssert toCFlags({ofCreate, ofAppend}) == (cCreat or cAppend)
```

```nim
{.emit: """
static int applyTwice(int (*cb)(void*, int), void* ud, int x) {
  return cb(ud, cb(ud, x));
}
""".}

proc cApplyTwice(cb: proc (ud: pointer; x: cint): cint {.cdecl, raises: [].};
                 ud: pointer; x: cint): cint {.importc: "applyTwice", nodecl.}

type Ctx = ref object
  f: proc (x: int): int {.raises: [].}

proc trampoline(ud: pointer; x: cint): cint {.cdecl, raises: [].} =
  let ctx = cast[Ctx](ud) # C hands back the pointer we gave it
  cint(ctx.f(int(x)))

proc applyTwice*(f: proc (x: int): int {.raises: [].}; x: int): int =
  ## Calls `f` twice through C.
  let ctx = Ctx(f: f)
  GC_ref(ctx)
  try:
    result = int(cApplyTwice(trampoline, cast[pointer](ctx), cint(x)))
  finally:
    GC_unref(ctx)

let step = 3
doAssert applyTwice(proc (x: int): int = x + step, 1) == 7
```
