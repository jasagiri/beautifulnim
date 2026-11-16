## E tests for docs/specification.md: BN-L2 (lints/nim.cfg rejects what it says it rejects).

import std/[os, osproc, strutils, unittest]

const root = currentSourcePath().parentDir.parentDir

proc nimCheck(dir, file: string): int =
  ## Exit code of `nim check` run in `dir`, so that only `dir/nim.cfg` (if any) applies.
  let (_, code) = execCmdEx("nim check --hints:off " & quoteShell(file), workingDir = dir)
  code

suite "BN-L2 lints/nim.cfg":
  test "Given each lints/check/cfg_*.nim, when checked with and without lints/nim.cfg, then only the first fails":
    let work = getTempDir() / "beautifulnim-lints"
    var seen = 0
    for path in walkFiles(root / "lints/check/cfg_*.nim"):
      removeDir(work)
      createDir(work)
      copyFile(path, work / "a.nim")
      let plain = nimCheck(work, "a.nim")
      copyFile(root / "lints/nim.cfg", work / "nim.cfg")
      let linted = nimCheck(work, "a.nim")
      if plain != 0 or linted == 0: echo "  ", path.extractFilename, ": plain=", plain, " linted=", linted
      check plain == 0
      check linted != 0
      inc seen
    removeDir(work)
    # one file per setting: every --warningAsError line, plus styleCheck
    var settings = 1
    for line in readFile(root / "lints/nim.cfg").splitLines:
      if line.startsWith("--warningAsError:"): inc settings
    check seen == settings
