## E tests for docs/specification.md: BN-X1..BN-X3 (the guides' code examples are real Nim),
## BN-X4..BN-X5 (the main guide fits one read and names every details file) and BN-X6 (the README's
## embedding example).

import std/[os, osproc, strutils, unittest]
import beautifulnim/[analyze, rules]

const root = currentSourcePath().parentDir.parentDir

type Example = object
  file: string
  line: int ## of the opening fence
  bad: bool
  code: string

proc examples(): seq[Example] =
  # A wildcard only in the last part of the pattern: on Windows a wildcard in a directory part
  # matches nothing, and every example check would pass on zero examples.
  var paths: seq[string]
  for skill in walkDirs(root / "skills" / "*"):
    if fileExists(skill / "SKILL.md"): paths.add skill / "SKILL.md"
    for path in walkFiles(skill / "details" / "*.md"): paths.add path
  for path in paths:
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

  test "BN-X1 Given each nim example, when checked under lints/nim.cfg, then nim check (and nim doc for runnableExamples) passes":
    for e in all:
      if e.bad: continue
      removeDir(work)
      createDir(work)
      copyFile(root / "lints/nim.cfg", work / "nim.cfg")
      writeFile(work / "example.nim", e.code)
      let (output, code) = execCmdEx("nim check --hints:off example.nim", workingDir = work)
      if code != 0: echo "  ", e.file, ":", e.line, "\n", output
      check code == 0
      if "runnableExamples" in e.code:
        let (docOut, docCode) = execCmdEx("nim doc --hints:off -o:example.html example.nim",
                                          workingDir = work)
        if docCode != 0: echo "  nim doc ", e.file, ":", e.line, "\n", docOut
        check docCode == 0
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

suite "BN-X guide layout":
  const guide = root / "skills/nim-best-practices/SKILL.md"
  const maxGuideChars = 28_000

  test "BN-X4 Given the main guide, when its length is measured, then it is at most 28 000 characters":
    let n = readFile(guide).len
    if n > maxGuideChars: echo "  ", guide.relativePath(root), " has ", n, " characters"
    check n <= maxGuideChars

  test "BN-X5 Given each skill, when its details files are listed, then SKILL.md names each and names no missing one":
    var skills = 0
    for skill in walkDirs(root / "skills/*"):
      inc skills
      let text = readFile(skill / "SKILL.md")
      for path in walkFiles(skill / "details/*.md"):
        let name = "details/" & path.extractFilename
        if name notin text: echo "  ", skill.relativePath(root), " does not name ", name
        check name in text
      var start = 0
      while true:
        let i = text.find("details/", start)
        if i < 0: break
        var j = i + "details/".len
        while j < text.len and text[j] in {'a'..'z', '0'..'9', '-', '.'}: inc j
        let name = text[i ..< j].strip(leading = false, chars = {'.'})
        # A name written as skills/<other>/details/x.md belongs to that other skill.
        var owner = skill
        let prefix = text[0 ..< i]
        let k = prefix.rfind("skills/")
        if k >= 0 and k + "skills/".len < i and prefix.find({' ', '`', '\n'}, k) < 0:
          owner = root / prefix[k ..< i].strip(leading = false, chars = {'/'})
        if name.endsWith(".md"):
          if not fileExists(owner / name): echo "  ", skill.relativePath(root), " names missing ", name
          check fileExists(owner / name)
        start = j
    check skills > 0 # a loop over nothing proves nothing (a wildcard that matches nothing passes)

suite "BN-X README":
  test "BN-X6 Given the README's nim block, when checked with the package and compiler paths, then it compiles without the semantic checker":
    var code, inside = false
    var example = ""
    for line in readFile(root / "README.md").splitLines:
      if not inside and line == "```nim":
        inside = true
        code = true
      elif inside and line.startsWith("```"):
        inside = false
      elif inside:
        example.add line & "\n"
    check code
    let work = getTempDir() / "beautifulnim-readme"
    removeDir(work)
    createDir(work)
    writeFile(work / "embed.nim", example)
    let (output, exit) = execCmdEx("nim check --path:" & quoteShell(root / "src") &
      " --path:" & quoteShell("$nim") & # $nim is Nim's, not the shell's
      " --hint:all:off --hint:Processing:on --processing:filenames embed.nim",
      workingDir = work)
    if exit != 0: echo output
    check exit == 0
    let imported = output.replace('\\', '/')
    check "/compiler/parser.nim" in imported # the syntax checker is there
    check "/compiler/sem.nim" notin imported # the semantic one is not
    removeDir(work)
