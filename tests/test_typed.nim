## E tests for docs/specification.md: BN-T5 (analyzeTyped without the standard library it needs).

import std/[os, strutils, unittest]
import beautifulnim/typed

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
    check a.errors.len == 1
    check a.errors[0].message.startsWith("cannot read: ")

  removeDir(work)
