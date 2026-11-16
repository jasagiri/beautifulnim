## E tests for docs/specification.md: BN-X1..BN-X3 (the guides' code examples are real Nim).

import std/[os, osproc, strutils, unittest]
import beautifulnim/[analyze, rules]

const root = currentSourcePath().parentDir.parentDir

type Example = object
  file: string
  line: int ## of the opening fence
  bad: bool
  code: string

proc examples(): seq[Example] =
  for path in walkFiles(root / "skills/*/SKILL.md"):
    var cur: Example
    var inside = false
    let lines = readFile(path).splitLines()
    for i, line in lines:
      if not inside and line.startsWith("```nim"):
        let info = line[3 .. ^1].strip
        doAssert info in ["nim", "nim bad"], path & ":" & $(i + 1) & ": unknown fence " & info.escape
        cur = Example(file: path.relativePath(root), line: i + 1, bad: info == "nim bad")
        inside = true
      elif inside and line.startsWith("```"):
        result.add cur
        inside = false
      elif inside:
        cur.code.add line & "\n"

suite "BN-X guide examples":
  let all = examples()
  let work = getTempDir() / "beautifulnim-examples"

  test "Given the guides, when examples are collected, then there are both good and bad ones":
    var good, bad = 0
    for e in all:
      if e.bad: inc bad
      else: inc good
    check good >= 5
    check bad >= 1

  test "BN-X1 Given each nim example, when checked under lints/nim.cfg, then nim check passes":
    for e in all:
      if e.bad: continue
      removeDir(work)
      createDir(work)
      copyFile(root / "lints/nim.cfg", work / "nim.cfg")
      writeFile(work / "example.nim", e.code)
      let (output, code) = execCmdEx("nim check --hints:off example.nim", workingDir = work)
      if code != 0: echo "  ", e.file, ":", e.line, "\n", output
      check code == 0
    removeDir(work)

  test "BN-X2 Given each nim example, when analyzed, then nothing at level warning or above is reported":
    for e in all:
      if e.bad: continue
      let a = analyze(e.code)
      check a.ok
      for f in a.findings:
        if f.level <= lvWarning:
          echo "  ", e.file, ":", e.line + f.line, ": ", f.rule, " ", f.title
          check false

  test "BN-X3 Given each nim bad example, when parsed, then it is valid syntax":
    for e in all:
      if not e.bad: continue
      let a = analyze(e.code)
      if not a.ok: echo "  ", e.file, ":", e.line, ": ", a.parseErrors
      check a.ok
