## E tests for docs/specification.md: BN-T5 (analyzeTyped without the standard library it needs)
## BN-T6 (BN-11, a type with `=destroy` and no `=copy`), BN-T7 (BN-05 on the symbols) and BN-L1 for the
## rules in TypedOnly.

import std/[os, strutils, unittest]
import beautifulnim/[rules, typed]

suite "BN-T5 standard library":
  let work = getTempDir() / "beautifulnim-typed"
  removeDir(work)
  createDir(work)
  let file = work / "a.nim"
  writeFile(file, "proc f*(x: bool) = discard\n")

  test "Given a stdlib directory without system.nim, when analyzeTyped runs, then nothing is checked and the error names the directory":
    let missing = work / "no-stdlib"
    let a = analyzeTyped(file, stdlib = missing)
    check not a.ok
    check a.findings.len == 0
    check a.errors.len == 1
    check a.errors[0].file == file
    check ("is not at " & missing) in a.errors[0].message

  test "Given the stdlib the checker was built with, when analyzeTyped runs on the same file, then BN-02 is reported":
    let a = analyzeTyped(file)
    check a.ok
    check a.findings.len == 1

  test "Given a path with no file, when analyzeTyped runs, then the read error is returned":
    let a = analyzeTyped(work / "missing.nim")
    check not a.ok
    check a.readError.len > 0
    check a.errors.len == 0

  removeDir(work)

suite "BN-T6 a type with =destroy and no =copy":
  let work = getTempDir() / "beautifulnim-typed-hooks"
  removeDir(work)
  createDir(work)

  proc bn11(source: string): seq[(int, int)] =
    ## Line and column of each BN-11 finding of `source`, which must compile.
    let file = work / "h.nim"
    writeFile(file, source)
    let a = analyzeTyped(file)
    if not a.ok: echo "  ", a.errors
    doAssert a.ok
    for f in a.findings:
      if f.rule == bn11DestroyWithoutCopy: result.add (f.line, f.col)

  const destroyOnly = "type\n  Pool = object\n    p: ptr int\n\n" &
    "proc `=destroy`(x: Pool) =\n  if x.p != nil: dealloc(x.p)\n"

  test "Given a type with =destroy and no =copy, when checked, then BN-11 is reported at the type's name":
    check bn11(destroyOnly) == @[(2, 3)]

  test "Given =copy marked {.error.}, when checked, then BN-11 is not reported":
    check bn11(destroyOnly & "proc `=copy`(d: var Pool; s: Pool) {.error.}\n").len == 0

  test "Given a deep =copy, when checked, then BN-11 is not reported":
    check bn11(destroyOnly & "proc `=copy`(d: var Pool; s: Pool) =\n" &
      "  if d.p != s.p:\n    `=destroy`(d)\n    d.p = nil\n" &
      "    if s.p != nil:\n      d.p = create(int)\n      d.p[] = s.p[]\n").len == 0

  test "Given only =dup and no =copy, when checked, then BN-11 is reported, since an assignment still copies the fields":
    check bn11(destroyOnly & "proc `=dup`(s: Pool): Pool =\n  result = Pool(p: nil)\n") == @[(2, 3)]

  test "Given a generic type with a generic =destroy and no =copy, when checked, then BN-11 is reported once":
    check bn11("type\n  Buf[T] = object\n    p: ptr T\n\n" &
      "proc `=destroy`[T](x: Buf[T]) =\n  if x.p != nil: dealloc(x.p)\n") == @[(2, 3)]

  test "Given types without hooks, and a field whose type has its own hooks, when checked, then BN-11 is not reported":
    check bn11("type\n  A = object\n    s: seq[int]\n  B = object\n    a: A\n    t: string\n").len == 0

  removeDir(work)

suite "BN-L1 lint check files of typed rules":
  const root = currentSourcePath().parentDir.parentDir

  test "Given lints/check/bn_NN.nim of each rule in TypedOnly, when analyzeTyped runs, then rule BN-NN is reported":
    for r in TypedOnly:
      let path = root / "lints/check" / ("bn_" & ($r)[3 .. 4] & ".nim")
      let a = analyzeTyped(path)
      check a.ok
      var hit = false
      for f in a.findings:
        if f.rule == r: hit = true
      if not hit: echo "  no ", r, " in ", path
      check hit

suite "BN-T7 BN-05 decided on the symbols":
  let work = getTempDir() / "beautifulnim-typed-naming"
  removeDir(work)
  createDir(work)

  proc bn05(source: string): seq[(int, int, Level)] =
    ## Line, column and level of each BN-05 finding of `source` with --typed; `source` must compile.
    let file = work / "n.nim"
    writeFile(file, source)
    let a = analyzeTyped(file)
    if not a.ok: echo "  ", a.errors
    doAssert a.ok
    for f in a.findings:
      if f.rule == bn05Naming: result.add (f.line, f.col, f.level)

  test "Given a C name declared through a {.pragma.} alias of importc, when checked, then BN-05 is not reported":
    check bn05("{.pragma: cfun, importc: \"do_thing\", cdecl.}\nproc do_thing(x: cint): cint {.cfun.}\n").len == 0

  test "Given a C type declared through a {.pragma.} alias of importc, when checked, then BN-05 is not reported":
    check bn05("{.pragma: ctype, importc: \"struct foo_bar\", header: \"<stdio.h>\".}\n" &
      "type foo_bar {.ctype.} = object\n").len == 0

  test "Given a C name declared under {.push importc.}, when checked, then BN-05 is not reported":
    check bn05("{.push importc, cdecl.}\nproc do_thing(x: cint): cint\n{.pop.}\n").len == 0

  test "Given a snake_case proc without a foreign name, when checked, then BN-05 is still reported":
    check bn05("proc do_thing*() = discard\n") == @[(1, 6, lvWarning)]

  test "Given a public getFoo whose parameter is an object, a ref object or a tuple, when checked, then BN-05 is reported at level info":
    check bn05("type\n  Person = object\n    name: string\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(4, 6, lvInfo)]
    check bn05("type\n  Person = ref object\n    name: string\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(4, 6, lvInfo)]
    check bn05("type\n  Pair = tuple[a, b: int]\n" &
      "proc getA*(p: var Pair): int = p.a\n") == @[(3, 6, lvInfo)]

  test "Given a public getFoo whose parameter is a string, an alias of one, or a generic, when checked, then BN-05 is not reported":
    check bn05("proc getValue*(key: string): string = key\n").len == 0
    check bn05("type Key = string\nproc getValue*(k: Key): string = k\n").len == 0
    check bn05("proc getValue*[T](k: T): T = k\n").len == 0

  removeDir(work)
