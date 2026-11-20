## E tests for docs/specification.md: BN-01..BN-10, BN-P1..BN-P3, BN-L1, BN-L3.

import std/[os, strutils, unittest]
import beautifulnim/[analyze, rules]

proc rulesOf(src: string): seq[RuleId] =
  let a = analyze(src)
  doAssert a.ok, "parse failed: " & $a.parseErrors
  for f in a.findings: result.add f.rule

proc reports(src: string; rule: RuleId): bool = rule in rulesOf(src)

proc reportedAt(src: string; rule: RuleId; line, col: int): bool =
  ## Whether `rule` is reported at exactly that place (1-based), e.g. on one parameter.
  for f in analyze(src).findings:
    if f.rule == rule and f.line == line and f.col == col: return true
  false

suite "BN-01 empty except":
  test "Given a bare except with only discard, when analyzed, then BN-01 is reported":
    check reports("try:\n  echo 1\nexcept:\n  discard\n", bn01EmptyExcept)
  test "Given a typed except with only discard, when analyzed, then BN-01 is reported":
    check reports("try:\n  echo 1\nexcept ValueError:\n  discard\n", bn01EmptyExcept)
  test "Given an except expression that discards, when analyzed, then BN-01 is reported":
    check reports("let x = try: 1 except CatchableError: discard\n", bn01EmptyExcept)
  test "Given an except that raises again, when analyzed, then BN-01 is not reported":
    check not reports("try:\n  echo 1\nexcept ValueError as e:\n  raise e\n", bn01EmptyExcept)
  test "Given an except that returns a value, when analyzed, then BN-01 is not reported":
    check not reports("let x = try: 1 except ValueError: 0\n", bn01EmptyExcept)
  test "Given the pattern inside a string and a comment, when analyzed, then nothing is reported":
    check rulesOf("let s = \"try: x except: discard\"\n# except: discard\n").len == 0

suite "BN-02 public bool parameter":
  test "Given a public proc with a bool parameter, when analyzed, then BN-02 is reported":
    check reports("proc open*(path: string; create: bool) = discard\n", bn02PublicBoolParam)
  test "Given grouped parameters a, b: bool on a public func, when analyzed, then BN-02 is reported at each name":
    check reportedAt("func f*(a, b: bool): int = 0\n", bn02PublicBoolParam, 1, 9)
    check reportedAt("func f*(a, b: bool): int = 0\n", bn02PublicBoolParam, 1, 12)
  test "Given a private proc with a bool parameter, when analyzed, then BN-02 is not reported":
    check not reports("proc open(path: string; create: bool) = discard\n", bn02PublicBoolParam)
  test "Given a public proc returning bool, when analyzed, then BN-02 is not reported":
    check not reports("proc isOpen*(path: string): bool = true\n", bn02PublicBoolParam)
  test "Given a public proc with a var bool parameter, when analyzed, then BN-02 is reported":
    check reports("proc f*(done: var bool) = discard\n", bn02PublicBoolParam)

  test "Given grouped parameters a, b: bool, when analyzed, then BN-02 is reported exactly once at each name and not at the type":
    var n = 0
    for f in analyze("func f*(a, b: bool): int = 0\n").findings:
      if f.rule == bn02PublicBoolParam: inc n
    check n == 2

suite "BN-03 converter":
  test "Given a converter, when analyzed, then BN-03 is reported":
    check reports("converter toInt(x: float): int = int(x)\n", bn03Converter)

suite "BN-04 silenced warnings":
  test "Given push warnings: off, when analyzed, then BN-04 is reported":
    check reports("{.push warnings: off.}\nproc f() = discard\n{.pop.}\n", bn04SilencedWarning)
  test "Given warning[UnusedImport]: off, when analyzed, then BN-04 is reported":
    check reports("{.warning[UnusedImport]: off.}\n", bn04SilencedWarning)
  test "Given hint[XDeclaredButNotUsed]: off under push, when analyzed, then BN-04 is reported":
    check reports("{.push hint[XDeclaredButNotUsed]: off.}\n{.pop.}\n", bn04SilencedWarning)
  test "Given warnings: on, when analyzed, then BN-04 is not reported":
    check not reports("{.push warnings: on.}\n{.pop.}\n", bn04SilencedWarning)

suite "BN-05 naming":
  test "Given a lowercase type name, when analyzed, then BN-05 is reported":
    check reports("type point = object\n  x: int\n", bn05Naming)
  test "Given a snake_case proc name, when analyzed, then BN-05 is reported":
    check reports("proc read_all() = discard\n", bn05Naming)
  test "Given an uppercase proc name, when analyzed, then BN-05 is reported":
    check reports("proc ReadAll() = discard\n", bn05Naming)
  test "Given a public getFoo getter, when analyzed, then BN-05 is reported at level info":
    let a = analyze("type P* = object\n  n: string\nproc getName*(p: P): string = p.n\n")
    check a.findings.len == 1
    check a.findings[0].rule == bn05Naming and a.findings[0].level == lvInfo
  test "Given an importc declaration with a C name, when analyzed, then BN-05 is not reported":
    check not reports("proc c_strlen(s: cstring): csize_t {.importc: \"strlen\", header: \"<string.h>\".}\n",
                      bn05Naming)
  test "Given an operator and NEP1 names, when analyzed, then BN-05 is not reported":
    check not reports("type Point = object\n  x: int\nproc `+`(a, b: Point): Point = a\nproc readAll() = discard\n",
                      bn05Naming)

  test "Given a public getFoo without a return type, or a private getFoo, when analyzed, then BN-05 is not reported":
    check not reports("proc getName*(p: int) = discard\n", bn05Naming)
    check not reports("proc getName(p: int): int = p\n", bn05Naming)
  test "Given a public routine named get or getA with one parameter and a return type, when analyzed, then only getA is reported at level info":
    check not reports("proc get*(p: int): int = p\n", bn05Naming)
    let a = analyze("proc getA*(p: int): int = p\n")
    check a.findings.len == 1
    check a.findings[0].rule == bn05Naming
    check a.findings[0].level == lvInfo
  test "Given a one-letter uppercase routine name and a one-letter lowercase type name, when analyzed, then BN-05 is reported at each":
    check reports("proc F*() = discard\n", bn05Naming)
    check reports("type t = int\n", bn05Naming)
  test "Given a snake_case routine and a lowercase type that carry pragmas other than a foreign name, when analyzed, then BN-05 is reported":
    check reports("proc do_it() {.inline.} = discard\n", bn05Naming)
    check reports("type color {.pure.} = enum\n  red\n", bn05Naming)
  test "Given an importc type with a C name, when analyzed, then BN-05 is not reported":
    check not reports("type foo_bar {.importc: \"struct foo_bar\", header: \"<x.h>\".} = object\n", bn05Naming)

suite "BN-06 include":
  test "Given an include statement, when analyzed, then BN-06 is reported":
    check reports("include other\n", bn06Include)

suite "BN-07 method":
  test "Given a method, when analyzed, then BN-07 is reported at level info":
    let a = analyze("type A = ref object of RootObj\nmethod draw(a: A) {.base.} = discard\n")
    check a.findings.len == 1
    check a.findings[0].rule == bn07Method and a.findings[0].level == lvInfo

suite "BN-08 dirty template":
  test "Given a template marked dirty, when analyzed, then BN-08 is reported":
    check reports("template t(x: int) {.dirty.} =\n  let y = x\n", bn08DirtyTemplate)
  test "Given a template that injects one name, when analyzed, then BN-08 is not reported":
    check not reports("template t(x: int) =\n  let y {.inject.} = x\n", bn08DirtyTemplate)
  test "Given a proc marked dirty in a comment, when analyzed, then BN-08 is not reported":
    check not reports("proc p() = discard # {.dirty.}\n", bn08DirtyTemplate)

  test "Given a template with a pragma other than dirty, when analyzed, then BN-08 is not reported":
    check not reports("template t*() {.used.} = discard\n", bn08DirtyTemplate)

suite "BN-09 code built from a string":
  test "Given parseStmt on a string in a macro, when analyzed, then BN-09 is reported":
    check reports("macro m(): untyped =\n  parseStmt(\"echo 1\")\n", bn09CodeFromString)
  test "Given parseExpr as a method call, when analyzed, then BN-09 is reported":
    check reports("macro m(): untyped =\n  result = \"1 + 1\".parseExpr\n", bn09CodeFromString)
  test "Given a qualified macros.parseStmt call, when analyzed, then BN-09 is reported once":
    let a = analyze("macro m(): untyped =\n  macros.parseStmt(\"echo 1\")\n")
    check a.findings.len == 1 and a.findings[0].rule == bn09CodeFromString
  test "Given a macro built with quote, when analyzed, then BN-09 is not reported":
    check not reports("macro m(): untyped =\n  quote do:\n    echo 1\n", bn09CodeFromString)

suite "BN-10 template argument used more than once":
  test "Given a public template that uses an untyped argument twice, when analyzed, then BN-10 is reported as a warning":
    let a = analyze("template sq*(x: untyped): untyped = x * x\n")
    check a.findings.len == 1
    check a.findings[0].rule == bn10RepeatedTemplateArg and a.findings[0].level == lvWarning
  test "Given a private template that uses an argument twice, when analyzed, then BN-10 is reported as info":
    let a = analyze("template sq(x: untyped): untyped = x * x\n")
    check a.findings.len == 1 and a.findings[0].level == lvInfo
  test "Given an argument used in two when conditions and once in the chosen branch, when analyzed, then BN-10 is not reported":
    check not reports("template t(c: int; x: int): int =\n  when c == 1: x\n  elif c == 2: x + 1\n  else: 0\n", bn10RepeatedTemplateArg)
  test "Given a template that uses a typed argument twice, when analyzed, then BN-10 is reported":
    check reports("template sq(x: int): int = x * x\n", bn10RepeatedTemplateArg)
  test "Given a template that binds the argument once with let, when analyzed, then BN-10 is not reported":
    check not reports("template sq(x: int): int =\n  let v = x\n  v * v\n", bn10RepeatedTemplateArg)
  test "Given an argument used once in each branch of an if, when analyzed, then BN-10 is not reported":
    check not reports("template t(c: bool; x: int): int =\n  if c: x + 1 else: x - 1\n", bn10RepeatedTemplateArg)
  test "Given an argument tested in an if and an elif condition and returned in else, when analyzed, then BN-10 is reported":
    check reportedAt("template clamp(x, lo, hi: int): int =\n  if x < lo: lo elif x > hi: hi else: x\n", bn10RepeatedTemplateArg, 1, 16)
  test "Given an argument used once in the case selector and once per branch, when analyzed, then BN-10 is reported":
    check reportedAt("template t(x: int): int =\n  case x\n  of 0: x\n  else: 1\n", bn10RepeatedTemplateArg, 1, 12)
  test "Given an argument used once in each of an if's later branches only, when analyzed, then BN-10 is not reported":
    check not reports("template t(c, d: bool; x: int): int =\n  if c: x elif d: x + 1 else: 0\n", bn10RepeatedTemplateArg)
  test "Given an argument used again inside astToStr and typeof, when analyzed, then BN-10 is not reported":
    check not reports("template check(c: bool) =\n  var t: typeof(c)\n  if not c: echo astToStr(c)\n", bn10RepeatedTemplateArg)
  test "Given a parameter that names a variable the template declares, when analyzed, then BN-10 is not reported":
    check not reports("template withX(x, body: untyped) =\n  var x = 0\n  inc x\n  body\n", bn10RepeatedTemplateArg)
  test "Given a parameter that names a variable the template declares and uses twice, when analyzed, then BN-10 is not reported":
    check not reports("template withX(x, body: untyped) =\n  var x = 0\n  inc x\n  inc x\n  body\n", bn10RepeatedTemplateArg)
  test "Given a parameter written as the type of two declarations, when analyzed, then BN-10 is not reported, since a type is not evaluated":
    check not reports("template newPair*(T: untyped) =\n  var a: T\n  var b: T\n", bn10RepeatedTemplateArg)
    check not reports("template c2*(T: untyped) =\n  const a: T = default(int)\n  let (b, c): (T, T) = (1, 2)\n", bn10RepeatedTemplateArg)
  test "Given a parameter written as a declared type and evaluated twice elsewhere, when analyzed, then BN-10 is reported":
    check reports("template t*(x: untyped) =\n  var a: x\n  echo x\n  echo x\n", bn10RepeatedTemplateArg)
  test "Given a parameter used as the initial value of two declarations, when analyzed, then BN-10 is reported":
    check reports("template t*(x: untyped) =\n  var a: int = x\n  var b = x\n", bn10RepeatedTemplateArg)
  test "Given an argument named again in runnableExamples, when analyzed, then BN-10 is not reported":
    check not reports("template t*(x: int): int =\n  runnableExamples:\n    doAssert t(1) == 1\n    echo x\n  x\n", bn10RepeatedTemplateArg)
  test "Given a typedesc parameter used twice, when analyzed, then BN-10 is not reported":
    check not reports("template z(T: typedesc): untyped = (default(T), default(T))\n", bn10RepeatedTemplateArg)
  test "Given an argument name used as a field after a dot, when analyzed, then only real uses count":
    check not reports("template f(o, x: untyped): untyped = o.x + x\n", bn10RepeatedTemplateArg)
  test "Given a proc that uses its parameter twice, when analyzed, then BN-10 is not reported":
    check not reports("proc sq(x: int): int = x * x\n", bn10RepeatedTemplateArg)

  test "Given a parameter that names a loop variable, a routine or the loop it runs over, when analyzed, then only the iterated argument used again is reported":
    check not reports("template t*(i: untyped) =\n  for i in 0 ..< 3:\n    echo i\n    echo i\n", bn10RepeatedTemplateArg)
    check not reports("template defProc*(name: untyped) =\n  proc name() = discard\n  name()\n", bn10RepeatedTemplateArg)
    check reports("template t*(x: untyped) =\n  for i in x: echo i\n  echo x\n", bn10RepeatedTemplateArg)
  test "Given an argument used once beside a bind statement and once as a named argument, when analyzed, then BN-10 is not reported":
    check not reports("template t*(x: untyped) =\n  bind echo\n  echo x\n", bn10RepeatedTemplateArg)
    check not reports("template t*(x: untyped) =\n  echo P(a: x)\n", bn10RepeatedTemplateArg)
  test "Given an argument used once after a when, an if or a case that does not use it, when analyzed, then BN-10 is not reported":
    check not reports("template t*(x: untyped) =\n  when defined(foo):\n    discard\n  echo x\n", bn10RepeatedTemplateArg)
    check not reports("template t*(x: untyped) =\n  if true:\n    discard\n  echo x\n", bn10RepeatedTemplateArg)
    check not reports("template t*(x: untyped) =\n  case 1\n  of 1: discard\n  else: discard\n  echo x\n", bn10RepeatedTemplateArg)
  test "Given an argument used twice in the else branch of a when or a case, when analyzed, then BN-10 is reported":
    check reports("template t*(x: untyped) =\n  when defined(foo):\n    discard\n  else:\n    echo x\n    echo x\n", bn10RepeatedTemplateArg)
    check reports("template t*(x: untyped) =\n  case 1\n  of 1: discard\n  else:\n    echo x\n    echo x\n", bn10RepeatedTemplateArg)
  test "Given an argument used as a case selector and once after the case, when analyzed, then BN-10 is reported":
    check reports("template t*(x: untyped) =\n  case x\n  of 1: discard\n  else: discard\n  echo x\n", bn10RepeatedTemplateArg)
  test "Given parameters of type typedesc[int] and static int used twice, when analyzed, then BN-10 is not reported":
    check not reports("template t*(T: typedesc[int]) =\n  var a: T\n  var b: T\n", bn10RepeatedTemplateArg)
    check not reports("template t*(n: static int) =\n  echo n\n  echo n\n", bn10RepeatedTemplateArg)
  test "Given an argument used once whose type name appears twice in the body, when analyzed, then BN-10 is not reported":
    check not reports("template t*(x: int) =\n  var a: int = x\n  var b: int\n", bn10RepeatedTemplateArg)

suite "finding contents":
  test "Given a violation on line 3 column 1, when analyzed, then the finding carries that place and the rule text":
    let a = analyze("let a = 1\n\nconverter toInt(x: float): int = int(x)\n")
    check a.findings.len == 1
    let f = a.findings[0]
    check f.line == 3 and f.col == 1
    check f.title == Rules[bn03Converter].title and f.fix == Rules[bn03Converter].fix
    check f.section == Rules[bn03Converter].section

suite "BN-P input":
  test "BN-P1 Given source with a syntax error, when analyzed, then ok is false and the message has a line":
    let a = analyze("proc f(\n  let = 3\n")
    check not a.ok
    check a.parseErrors.len >= 1
    check a.parseErrors[0].line >= 1 and a.parseErrors[0].message.len > 0
  test "BN-P2 Given empty source, when analyzed, then ok with no findings":
    let a = analyze("")
    check a.ok and a.findings.len == 0
  test "BN-P3 Given source over the limit, when analyzed, then ok is false and the limit is named":
    let a = analyze(repeat('#', MaxSourceBytes + 1))
    check not a.ok
    check "MaxSourceBytes" in a.parseErrors[0].message or $MaxSourceBytes in a.parseErrors[0].message

  test "BN-P1 Given a syntax error at line 1 column 9, when analyzed, then the first parse error carries that place":
    let a = analyze("proc f( = discard\n")
    check not a.ok
    check a.parseErrors.len > 0
    check a.parseErrors[0].line == 1
    check a.parseErrors[0].col == 9
  test "BN-P1 Given source with exactly one syntax error, when analyzed, then ok is false with that one error":
    let a = analyze("let x = (1\n")
    check not a.ok
    check a.parseErrors.len == 1
  test "BN-P3 Given source of exactly 1 MiB and of 1 MiB and one byte, when analyzed, then only the longer one is refused":
    let atLimit = "#" & repeat(' ', (1 shl 20) - 2) & "\n"
    check atLimit.len == 1 shl 20
    check analyze(atLimit).ok
    let over = analyze(atLimit & " ")
    check not over.ok
    check over.parseErrors.len == 1

suite "BN-L lint check files":
  const root = currentSourcePath().parentDir.parentDir
  test "BN-L1 Given each lints/check/bn_NN.nim of a syntax rule, when analyzed, then rule BN-NN is reported":
    # The files of TypedOnly rules are checked with analyzeTyped in tests/test_typed.nim.
    var seen = 0
    for path in walkFiles(root / "lints/check/bn_*.nim"):
      let id = "BN-" & path.extractFilename[3 .. 4]
      inc seen
      var typedOnly = false
      for r in TypedOnly:
        if $r == id: typedOnly = true
      if typedOnly: continue
      let found = rulesOf(readFile(path))
      var hit = false
      for r in found:
        if $r == id: hit = true
      check hit
      if not hit: echo "  no ", id, " in ", path
    check seen == RuleId.high.ord + 1 # one file per rule
  test "BN-L3 Given the package's own src/, when analyzed, then there are no findings":
    var seen = 0
    for path in walkDirRec(root / "src"):
      if path.endsWith(".nim"):
        inc seen
        let a = analyze(readFile(path))
        check a.ok
        if a.findings.len > 0: echo "  ", path, ": ", a.findings
        check a.findings.len == 0
    check seen > 0 # a loop over nothing proves nothing
