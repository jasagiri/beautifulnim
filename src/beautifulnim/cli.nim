## `beautifulnim check [options] <file.nim>...` and `beautifulnim rules` (docs/specification.md, BN-C).

import std/[json, parseopt]
import ./[analyze, report, rules]

const Usage = """beautifulnim — check Nim source against BeautifulNim's machine-checkable rules

Usage:
  beautifulnim check [--min-level:error|warning|info] [--format:text|json] <file.nim>...
  beautifulnim rules
  beautifulnim --help

Exit status: 0 no findings at or above the level, 1 findings, 2 usage error,
unreadable file or a file that is not valid Nim."""

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

proc check(files: seq[string]; minLevel: Level; format: Format): int =
  var status = 0
  var reports = newJArray()
  for path in files:
    let source =
      try: readFile(path)
      except IOError as e:
        stderr.writeLine path, ": cannot read: ", e.msg
        status = 2
        continue
    let a = analyze(source)
    if not a.ok:
      for e in a.parseErrors:
        stderr.writeLine path, ":", e.line, ":", e.col, ": not valid Nim: ", e.message
      status = 2
      continue
    let shown = a.findings.atOrAbove(minLevel)
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
    else: check(files, minLevel, format)
  of "":
    stderr.writeLine Usage
    2
  else:
    stderr.writeLine "unknown command '", command, "'\n\n", Usage
    2

when isMainModule:
  quit(main())
