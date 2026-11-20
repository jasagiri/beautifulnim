## E tests for docs/specification.md: BN-T5 (analyzeTyped without the standard library it needs)
## BN-T6 (BN-11, a type with `=destroy` and no `=copy`), BN-T7 (BN-05 on the symbols), BN-T8 (BN-12, a
## returned cstring whose string is freed on return) and BN-L1 for the rules in TypedOnly.

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

suite "BN-T2 any file that compiles":
  let work = getTempDir() / "beautifulnim-typed-any"
  removeDir(work)
  createDir(work)

  test "Given a public enum, const, let and a proc using them at the top level, when analyzeTyped runs, then it succeeds with no findings":
    let file = work / "e.nim"
    writeFile(file, "type Color* = enum\n  cRed, cGreen\nconst k* = 3\nlet v* = cRed\nproc show*(c: Color): string = $c\n")
    let a = analyzeTyped(file)
    check a.ok
    check a.errors.len == 0
    check a.findings.len == 0

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

  test "Given an alias of string and a distinct string that is converted to, when checked, then BN-11 is not reported, since their =destroy is the one system gives string":
    check bn11("type D = string\n").len == 0
    check bn11("type D = distinct string\nlet d = D(\"a\")\necho string(d)\n").len == 0

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

  test "Given a public getFoo whose object, ref object or tuple parameter has a field foo, when checked, then BN-05 is reported at level warning":
    check bn05("type\n  Person = object\n    name: string\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(4, 6, lvWarning)]
    check bn05("type\n  Person = ref object\n    name: string\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(4, 6, lvWarning)]
    check bn05("type\n  Pair = tuple[a, b: int]\n" &
      "proc getA*(p: var Pair): int = p.a\n") == @[(3, 6, lvWarning)]

  test "Given a public getFoo whose field foo is inherited or written in another style, when checked, then BN-05 is reported at level warning":
    check bn05("type\n  Base = object of RootObj\n    name: string\n  Person = object of Base\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(5, 6, lvWarning)]
    check bn05("type\n  Person = object\n    full_name: string\n" &
      "proc getFullName*(p: Person): string = p.full_name\n").contains((4, 6, lvWarning))

  test "Given a public getFoo whose object parameter has no field foo, when checked, then BN-05 stays at level info":
    check bn05("type\n  Rect = object\n    w, h: int\n" &
      "proc getArea*(r: Rect): int = r.w * r.h\n") == @[(4, 6, lvInfo)]

  test "Given a public getFoo whose parameter is a string, an alias of one, or a generic, when checked, then BN-05 is not reported":
    check bn05("proc getValue*(key: string): string = key\n").len == 0
    check bn05("type Key = string\nproc getValue*(k: Key): string = k\n").len == 0
    check bn05("proc getValue*[T](k: T): T = k\n").len == 0

  test "Given public routines named getFoo with no parameter or two, and one named get, when checked, then nothing fails and BN-05 is not reported":
    check bn05("type\n  P = object\n    foo: int\nproc getFoo*(): int = 1\nproc getFoo*(a, b: P): int = a.foo\n" &
      "proc get*(p: P): int = p.foo\n").len == 0

  test "Given a type named getThing, when checked, then BN-05 stays as the syntax rule reports it":
    check bn05("type getThing* = object\n  a: int\n") == @[(1, 6, lvWarning)]

  test "Given a public getFoo whose field is inherited through a ref base, when checked, then BN-05 is reported at level warning":
    check bn05("type\n  Base = ref object of RootObj\n    name: string\n  Person = ref object of Base\n" &
      "proc getName*(p: Person): string = p.name\n") == @[(5, 6, lvWarning)]

  test "Given a public getFoo whose tuple parameter has no field foo, when checked, then BN-05 stays at level info":
    check bn05("type\n  Pair = tuple[a, b: int]\nproc getC*(p: Pair): int = p.a\n") == @[(3, 6, lvInfo)]

  removeDir(work)

suite "BN-T8 a returned cstring whose string is freed on return":
  let work = getTempDir() / "beautifulnim-typed-cstring"
  removeDir(work)
  createDir(work)

  proc bn12(source: string): seq[int] =
    ## The line of each BN-12 finding of `source` with --typed; `source` must compile.
    let file = work / "c.nim"
    writeFile(file, source)
    let a = analyzeTyped(file)
    if not a.ok: echo "  ", a.errors
    doAssert a.ok
    for f in a.findings:
      if f.rule == bn12DanglingCstring: result.add f.line

  test "Given a cstring of a temporary string returned as the last expression, when checked, then BN-12 is reported":
    check bn12("proc cname*(s: string): cstring =\n  cstring(s & \"\\0\")\n") == @[2]

  test "Given a routine with a doc comment that returns a cstring of a field joined with another string, when checked, then BN-12 is reported":
    check bn12("type\n  P = object\n    label: string\nproc cname*(p: P): cstring =\n  ## For C.\n" &
      "  cstring(p.label & \"\\0\")\n") == @[6]

  test "Given a cstring of a local variable assigned to result, when checked, then BN-12 is reported":
    check bn12("proc f*(x: int): cstring =\n  let s = \"a\" & $x\n  result = s.cstring\n") == @[3]

  test "Given a cstring of a temporary in a return statement of a private proc, when checked, then BN-12 is reported":
    check bn12("proc f(x: int): cstring =\n  return cstring($x)\ndiscard f(1)\n") == @[2]

  test "Given a cstring of a sink parameter, when checked, then BN-12 is reported":
    check bn12("proc f*(s: sink string): cstring =\n  cstring(s)\n") == @[2]

  test "Given a cstring of a temporary that is the value of a block, if, case or try expression, when checked, then BN-12 is reported in that branch":
    check bn12("proc f*(s: string): cstring =\n  result = (block:\n    cstring(s & \"x\"))\n") == @[3]
    check bn12("proc f*(s: string; k: int): cstring =\n  result = if k > 0: cstring(s & \"x\") else: nil\n") == @[2]
    check bn12("proc f*(s: string; k: int): cstring =\n  if k > 0: cstring(\"lit\") else: cstring(s & \"x\")\n") == @[2]
    check bn12("proc f*(s: string; k: int): cstring =\n  case k\n  of 0: cstring(s & \"x\")\n  else: nil\n") == @[3]
    check bn12("proc f*(s: string): cstring =\n  try: cstring(s & \"x\")\n  except CatchableError: cstring($s.len)\n") == @[2, 3]

  test "Given an if expression whose branches are a literal and nil, when checked, then BN-12 is not reported":
    check bn12("proc f*(k: int): cstring =\n  if k > 0: cstring(\"lit\") else: nil\n").len == 0

  test "Given a cstring of a parameter, a field of one, a global or a literal, when checked, then BN-12 is not reported":
    check bn12("proc f*(s: string): cstring =\n  cstring(s)\n").len == 0
    check bn12("type\n  P = object\n    label: string\nproc f*(p: P): cstring =\n  cstring(p.label)\n").len == 0
    check bn12("var g = \"abc\"\nproc f*(): cstring =\n  cstring(g)\n").len == 0
    check bn12("proc f*(): cstring =\n  cstring(\"abc\")\n").len == 0

  test "Given a cstring converted from a local cstring, when checked, then BN-12 is not reported, since no string is freed":
    check bn12("proc f*(): cstring =\n  let c: cstring = \"a\"\n  result = cstring(c)\n").len == 0

  test "Given a cstring returned by a call and a conversion of a temporary to a distinct string, when checked, then BN-12 is not reported":
    check bn12("proc g(x: string): cstring = \"lit\"\nproc h*(s: string): cstring = g(s & \"x\")\n").len == 0
    check bn12("type D = distinct string\nproc f*(s: string): D = D(s & \"x\")\n").len == 0

  test "Given cstring(s & \"\\0\") at line 2 column 3, when checked with --typed, then BN-12 is reported at the conversion, the opening parenthesis at column 10":
    let file = work / "c.nim"
    writeFile(file, "proc cname*(s: string): cstring =\n  cstring(s & \"\\0\")\n")
    var places: seq[(int, int)]
    for f in analyzeTyped(file).findings:
      if f.rule == bn12DanglingCstring: places.add (f.line, f.col)
    check places == @[(2, 10)]

  removeDir(work)
