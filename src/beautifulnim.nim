## BeautifulNim's checker: the machine-checkable rules of `skills/nim-best-practices/SKILL.md`,
## read from the tree Nim's own parser builds (docs/adr/ADR-BNIM-0001).
## Importing it needs Nim's `compiler/` on the path (`--path:"$nim"`).

import beautifulnim/[analyze, report, rules]
export analyze, report, rules
