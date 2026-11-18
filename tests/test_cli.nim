## E tests for docs/specification.md: BN-C1..BN-C6 and BN-T1..BN-T4 (the `beautifulnim` command).

import std/[json, os, osproc, sequtils, strutils, unittest]

const root = currentSourcePath().parentDir.parentDir
let work = getTempDir() / "beautifulnim-cli"
let exe = work / "beautifulnim".addFileExt(ExeExt)

proc run(args: string): tuple[output: string, code: int] =
  ## stderr is merged by execCmdEx itself (poStdErrToStdOut). No `2>&1`: on Windows the command
  ## does not go through a shell, so it would reach the program as a file name.
  let (output, code) = execCmdEx(quoteShell(exe) & " " & args)
  (output, code)

proc sample(name, code: string): string =
  result = work / name
  writeFile(result, code)

suite "BN-C command":
  removeDir(work)
  createDir(work)
  # -o: the tests call the binary at a known place.
  let (buildOut, buildCode) = execCmdEx("nim c --hints:off -o:" & quoteShell(exe) & " " &
                                        quoteShell(root / "src/beautifulnim/cli.nim"))
  doAssert buildCode == 0, buildOut

  test "BN-C1 Given a file with a converter, when checked, then a compiler-style line is printed and the exit is 1":
    let f = sample("conv.nim", "let a = 1\nconverter toInt(x: float): int = int(x)\n")
    let (output, code) = run("check " & quoteShell(f))
    check code == 1
    check output.strip == f & ":2:1: error: [BN-03] a converter; " &
      "call an explicit conversion proc; converters silently erase the distinction a type draws"

  test "BN-C1 Given a clean file, when checked, then nothing is printed and the exit is 0":
    let f = sample("clean.nim", "proc readAll*(path: string): string = path\n")
    let (output, code) = run("check " & quoteShell(f))
    check code == 0
    check output.strip == ""

  test "BN-C2 Given only info findings and --min-level:warning, when checked, then the exit is 0":
    let f = sample("info.nim", "type A = ref object of RootObj\nmethod m(a: A) {.base.} = echo 1\n")
    check run("check " & quoteShell(f)).code == 1
    let (output, code) = run("check --min-level:warning " & quoteShell(f))
    check code == 0 and output.strip == ""

  test "BN-C3 Given --format:json, when checked, then each file has its findings as JSON":
    let f = sample("conv2.nim", "converter c(x: float): int = int(x)\n")
    let (output, code) = execCmdEx(quoteShell(exe) & " check --format:json " & quoteShell(f))
    check code == 1
    let j = parseJson(output)
    check j[0]["file"].getStr == f
    check j[0]["findings"][0]["rule"].getStr == "BN-03"
    check j[0]["findings"][0]["line"].getInt == 1

  test "BN-C4 Given a file that is not valid Nim, when checked, then the parser's message is printed and the exit is 2":
    let f = sample("broken.nim", "proc f(\n")
    let (output, code) = run("check " & quoteShell(f))
    check code == 2
    check (f & ":2:1: not valid Nim: ") in output

  test "BN-C4 Given a missing file, when checked, then the exit is 2":
    check run("check " & quoteShell(work / "nope.nim")).code == 2

  test "BN-C5 Given no command, an unknown option or check without files, when run, then usage and exit 2":
    for args in ["", "check", "check --loud x.nim", "frobnicate", "check --min-level:loud x.nim",
                 "check --typed:yes x.nim"]:
      let (output, code) = run(args)
      check code == 2
      check "Usage:" in output

  test "BN-C5 Given rules, when run, then every rule is listed and the exit is 0":
    let (output, code) = run("rules")
    check code == 0
    for id in ["BN-01", "BN-02", "BN-03", "BN-04", "BN-05", "BN-06", "BN-07"]:
      check id in output

suite "BN-T typed":
  # each test compiles its sample with the semantic checker, as `nim check` would

  proc rulesAt(output: string): seq[string] =
    ## "line:col rule" for each finding line of the text output.
    for line in output.splitLines:
      let parts = line.split(": ")
      if parts.len >= 3 and "[BN-" in line:
        let place = parts[0].split(':')
        result.add place[^2] & ":" & place[^1] & " " & line[line.find("[BN-") + 1 ..< line.find("]")]

  test "BN-T1 Given a bool behind an alias, when checked with --typed, then BN-02 is reported and without it not":
    let f = sample("alias.nim", "type Flag = bool\nproc f*(x: Flag; y: var Flag) = discard\n")
    check run("check " & quoteShell(f)).code == 0
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 1
    check output.rulesAt == @["2:9 BN-02", "2:18 BN-02"]

  test "BN-T1 Given distinct bool, a private routine and a generic parameter, when checked with --typed, then nothing is reported":
    let f = sample("quiet.nim", "type D = distinct bool\nproc f*(x: D) = discard\n" &
                   "proc g(x: bool) = discard\nproc h*[T](x: T) = discard\n")
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 0
    check output.strip == ""

  test "BN-T2 Given a plain bool and a converter, when checked with --typed, then each is reported once":
    let f = sample("both.nim", "proc f*(a, b: bool) = discard\nconverter c(x: float): int = int(x)\n")
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 1
    check output.rulesAt == @["1:9 BN-02", "1:12 BN-02", "2:1 BN-03"]

  test "BN-T3 Given a nim.cfg that adds a path, when checked with --typed, then the import through it resolves":
    let dir = work / "withcfg"
    createDir(dir / "lib")
    writeFile(dir / "nim.cfg", "--path:\"lib\"\n")
    writeFile(dir / "lib" / "flags.nim", "type Flag* = bool\n")
    writeFile(dir / "main.nim", "import flags\nproc f*(x: Flag) = discard\n")
    let (output, code) = run("check --typed " & quoteShell(dir / "main.nim"))
    check code == 1
    check output.rulesAt == @["2:9 BN-02"]

  test "BN-C6 Given a file that parses but does not compile, when checked with --typed, then the compiler's errors and exit 2":
    let f = sample("wrong.nim", "let y: int = \"s\"\n")
    check run("check " & quoteShell(f)).code == 0
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 2
    check (f & ":1:14: does not compile: type mismatch") in output

  test "BN-T1 Given each kind of public routine, sink and a generic alias, when checked with --typed, then each bool parameter is reported":
    let f = sample("kinds.nim", "proc s*(x: sink bool) = discard\n" &
      "template t*(x: bool): untyped = x\n" &
      "macro m*(x: bool): untyped = discard\n" &
      "iterator it*(x: bool): int = yield 1\n" &
      "func fn*(x: bool): int = 0\n" &
      "type O = object of RootObj\n" &
      "method me*(o: O; x: bool) {.base.} = discard\n" &
      "type G[T] = bool\n" &
      "proc g*(x: G[int]) = discard\n")
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 1
    check output.rulesAt == @["1:9 BN-02", "2:13 BN-02", "3:10 BN-02", "4:14 BN-02", "5:10 BN-02",
                              "7:1 BN-07", "7:18 BN-02", "9:9 BN-02"]

  test "BN-T1 Given a bool parameter on a routine of an imported module, when the importer is checked with --typed, then it is not reported":
    let dir = work / "imported"
    createDir(dir / "lib")
    writeFile(dir / "lib" / "other.nim", "proc o*(x: bool) = discard\n")
    writeFile(dir / "main.nim", "import lib/other\nproc f*(x: int) = o(true)\n")
    let (output, code) = run("check --typed " & quoteShell(dir / "main.nim"))
    check code == 0
    check output.strip == ""

  test "BN-T3 Given a config.nims that defines a symbol, when checked with --typed, then code under that symbol is checked":
    let dir = work / "withnims"
    createDir(dir)
    writeFile(dir / "config.nims", "switch(\"define\", \"fromNims\")\n")
    writeFile(dir / "main.nim", "when defined(fromNims):\n  type Flag* = bool\nproc f*(x: Flag) = discard\n")
    let (output, code) = run("check --typed " & quoteShell(dir / "main.nim"))
    check code == 1
    check output.rulesAt == @["3:9 BN-02"]

  test "BN-T4 Given a .nims file, when checked with --typed, then it is checked as NimScript":
    # switch exists only in NimScript, so this compiles only when the file is checked as NimScript
    let f = sample("script.nims", "type Flag = bool\nproc f*(x: Flag) = discard\nswitch(\"define\", \"x\")\n")
    let (output, code) = run("check --typed " & quoteShell(f))
    check code == 1
    check output.rulesAt == @["2:9 BN-02"]

  test "BN-C6 Given an import that does not compile, when checked with --typed, then the error names the imported file, once":
    let dir = work / "importerr"
    createDir(dir / "lib")
    writeFile(dir / "lib" / "broken.nim", "proc g*() = undefinedThing()\n")
    writeFile(dir / "main.nim", "import lib/broken\nproc f*() = g()\n")
    let (output, code) = run("check --typed " & quoteShell(dir / "main.nim"))
    check code == 2
    var lines: seq[string]
    for line in output.splitLines:
      if "does not compile:" in line: lines.add line
    check lines.len > 0
    for line in lines:
      check line.contains("broken.nim:1:")
    check lines.deduplicate.len == lines.len
