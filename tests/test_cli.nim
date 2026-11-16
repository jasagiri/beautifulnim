## E tests for docs/specification.md: BN-C1..BN-C5 (the `beautifulnim` command).

import std/[json, os, osproc, strutils, unittest]

const root = currentSourcePath().parentDir.parentDir
let work = getTempDir() / "beautifulnim-cli"
let exe = work / "beautifulnim"

proc run(args: string): tuple[output: string, code: int] =
  let (output, code) =
    execCmdEx(quoteShell(exe) & " " & args & " 2>&1")
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
    for args in ["", "check", "check --loud x.nim", "frobnicate", "check --min-level:loud x.nim"]:
      let (output, code) = run(args)
      check code == 2
      check "Usage:" in output

  test "BN-C5 Given rules, when run, then every rule is listed and the exit is 0":
    let (output, code) = run("rules")
    check code == 0
    for id in ["BN-01", "BN-02", "BN-03", "BN-04", "BN-05", "BN-06", "BN-07"]:
      check id in output
