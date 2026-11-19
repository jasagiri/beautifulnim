## `beautifulnim check [options] <file.nim>...` and `beautifulnim rules` (docs/specification.md, BN-C).

import std/[json, parseopt]
import ./[analyze, report, rules, typed]

const Usage = """beautifulnim — check Nim source against BeautifulNim's machine-checkable rules

Usage:
  beautifulnim check [--min-level:error|warning|info] [--format:text|json] [--typed] <file.nim>...
  beautifulnim rules
  beautifulnim --help

--typed  check each file as `nim check` does (its nim.cfg and imports apply) and
         decide BN-02 on the resolved types, so `type Flag = bool` counts as bool

Exit status: 0 no findings at or above the level, 1 findings, 2 usage error,
unreadable file, a file that is not valid Nim or, with --typed, does not compile."""

type Format = enum
  fmText = "text"
  fmJson = "json"

proc parseFormat(s: string): Format {.raises: [ValueError].} =
  for f in Format:
    if $f == s: return f
  raise newException(ValueError, "format must be text or json; got '" & s & "'")

proc listRules(): int =
  for id, r in Rules:
    echo $id, "  ", $r.level, "  ", r.title, " (", r.section, ")"
  0

type Mode = enum
  modeSyntax ## rules on the syntax tree only (ADR-BNIM-0001)
  modeTyped  ## BN-02 on resolved types (ADR-BNIM-0003)

proc cannotRead(path, why: string; status: var int) =
  stderr.writeLine path, ": cannot read: ", why
  status = 2

proc findingsOf(path: string; mode: Mode; status: var int): (bool, seq[Finding]) =
  ## The findings, or false after printing why the file could not be checked. The file is read
  ## once: here for the syntax rules, by analyzeTyped (which the compiler's reading must match)
  ## with --typed.
  case mode
  of modeSyntax:
    let source =
      try: readFile(path)
      except IOError as e:
        cannotRead(path, e.msg, status)
        return (false, @[])
    let a = analyze(source)
    if not a.ok:
      for e in a.parseErrors:
        stderr.writeLine path, ":", e.line, ":", e.col, ": not valid Nim: ", e.message
      status = 2
    (a.ok, a.findings)
  of modeTyped:
    let a = analyzeTyped(path)
    if a.readError.len > 0:
      cannotRead(path, a.readError, status)
    elif not a.ok:
      for e in a.errors:
        # an error the compiler gives no place for (an invalid module name) belongs to the checked file
        let file = if e.file.len > 0: e.file else: path
        stderr.writeLine file, ":", e.line, ":", e.col, ": does not compile: ", e.message
      status = 2
    (a.ok, a.findings)

proc check(files: seq[string]; minLevel: Level; format: Format; mode: Mode): int =
  var status = 0
  var reports = newJArray()
  for path in files:
    let (ok, findings) = findingsOf(path, mode, status)
    if not ok: continue
    let shown = findings.atOrAbove(minLevel)
    if shown.len > 0 and status == 0: status = 1
    case format
    of fmText:
      for f in shown: echo textLine(path, f)
    of fmJson:
      var items = newJArray()
      for f in shown: items.add %f
      reports.add %*{"file": path, "findings": items}
  if format == fmJson: echo pretty(reports)
  status

proc main(): int =
  var command = ""
  var files: seq[string]
  var minLevel = lvInfo
  var format = fmText
  var mode = modeSyntax
  try:
    for kind, key, val in getopt():
      case kind
      of cmdArgument:
        if command.len == 0: command = key
        else: files.add key
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "h":
          echo Usage
          return 0
        of "min-level": minLevel = parseLevel(val)
        of "format": format = parseFormat(val)
        of "typed":
          if val.len > 0: raise newException(ValueError, "--typed takes no value; got '" & val & "'")
          mode = modeTyped
        else: raise newException(ValueError, "unknown option --" & key)
      of cmdEnd: discard
  except ValueError as e:
    stderr.writeLine e.msg, "\n\n", Usage
    return 2
  case command
  of "rules": listRules()
  of "check":
    if files.len == 0:
      stderr.writeLine "check needs at least one file\n\n", Usage
      2
    else: check(files, minLevel, format, mode)
  of "":
    stderr.writeLine Usage
    2
  else:
    stderr.writeLine "unknown command '", command, "'\n\n", Usage
    2

when isMainModule:
  quit(main())
