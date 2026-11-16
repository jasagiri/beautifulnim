## Findings as JSON and as compiler-style text lines, shared by the CLI and by tools that embed
## the checker.

import std/json
import ./[analyze, rules]

func `%`*(f: Finding): JsonNode =
  %*{"rule": $f.rule, "level": $f.level, "line": f.line, "col": f.col,
     "title": f.title, "fix": f.fix, "section": f.section}

func atOrAbove*(findings: openArray[Finding]; minLevel: Level): seq[Finding] =
  ## The findings whose level is `minLevel` or more severe.
  for f in findings:
    if f.level <= minLevel: result.add f

func textLine*(path: string; f: Finding): string =
  ## `path:line:col: level: [BN-NN] title; fix`, the shape editors and CI parse.
  path & ":" & $f.line & ":" & $f.col & ": " & $f.level & ": [" & $f.rule & "] " & f.title &
    "; " & f.fix
