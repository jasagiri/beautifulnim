## E tests for docs/specification.md: BN-01..BN-07, BN-P1..BN-P3, BN-L1, BN-L3.

import std/[os, strutils, unittest]
import beautifulnim/[analyze, rules]

proc rulesOf(src: string): seq[RuleId] =
  let a = analyze(src)
  doAssert a.ok, "parse failed: " & $a.parseErrors
  for f in a.findings: result.add f.rule

proc reports(src: string; rule: RuleId): bool = rule in rulesOf(src)

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
  test "Given grouped parameters a, b: bool on a public func, when analyzed, then BN-02 is reported":
    check reports("func f*(a, b: bool): int = 0\n", bn02PublicBoolParam)
  test "Given a private proc with a bool parameter, when analyzed, then BN-02 is not reported":
    check not reports("proc open(path: string; create: bool) = discard\n", bn02PublicBoolParam)
  test "Given a public proc returning bool, when analyzed, then BN-02 is not reported":
    check not reports("proc isOpen*(path: string): bool = true\n", bn02PublicBoolParam)
  test "Given a public proc with a var bool parameter, when analyzed, then BN-02 is reported":
    check reports("proc f*(done: var bool) = discard\n", bn02PublicBoolParam)

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

suite "BN-06 include":
  test "Given an include statement, when analyzed, then BN-06 is reported":
    check reports("include other\n", bn06Include)

suite "BN-07 method":
  test "Given a method, when analyzed, then BN-07 is reported at level info":
    let a = analyze("type A = ref object of RootObj\nmethod draw(a: A) {.base.} = discard\n")
    check a.findings.len == 1
    check a.findings[0].rule == bn07Method and a.findings[0].level == lvInfo

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

suite "BN-L lint check files":
  const root = currentSourcePath().parentDir.parentDir
  test "BN-L1 Given each lints/check/bn_NN.nim, when analyzed, then rule BN-NN is reported":
    var seen = 0
    for path in walkFiles(root / "lints/check/bn_*.nim"):
      let id = "BN-" & path.extractFilename[3 .. 4]
      let found = rulesOf(readFile(path))
      var hit = false
      for r in found:
        if $r == id: hit = true
      check hit
      if not hit: echo "  no ", id, " in ", path
      inc seen
    check seen == RuleId.high.ord + 1
  test "BN-L3 Given the package's own src/, when analyzed, then there are no findings":
    for path in walkDirRec(root / "src"):
      if path.endsWith(".nim"):
        let a = analyze(readFile(path))
        check a.ok
        if a.findings.len > 0: echo "  ", path, ": ", a.findings
        check a.findings.len == 0
