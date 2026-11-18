# Defect census — BeautifulNim

Each class was found from one defect and then counted over `src/`, `tests/`, `config.nims` and
`.github/`. The populations are small, so every hit was read by hand (no sampling).

## Two readers of one input (2026-11-19)

Found: `analyzeTyped(path, source)` checked the syntax rules on `source` while the compiler read
`path` from disk; a missing file gave no finding and no error.

| Where | State |
|---|---|
| `analyzeTyped` | fixed: takes `path` only and reads the file itself |
| `cli.findingsOf(path, source)`: with `--typed` the CLI read the file and `analyzeTyped` read it again | fixed: each mode reads the file once (`readError` carries the read failure) |

Gate: none. Which code reads an input is a design property, not a pattern a test can count; the
spec (BN-T5) states that `analyzeTyped` reads the file.

## Shell syntax in a command that does not go through a shell (2026-11-19)

Found: `execCmdEx(... & " 2>&1")`. On Windows `execCmdEx` starts the program without a shell, so
`2>&1` reached it as a file name; on POSIX it was redundant (`poStdErrToStdOut` is the default).

Population: 8 `execCmdEx`/`exec` calls. After the fix none contains `>`, `|`, `&&`, `2>&1`;
`$nim` in BN-X6 is passed through `quoteShell` so POSIX shells do not expand it.

Gate: `nim test` on Windows in CI (`.github/workflows/test.yml`).

## A loop over discovered files that passes on zero files (2026-11-19)

Found: `walkFiles(root / "skills/*/SKILL.md")` matched nothing on Windows (a wildcard works only in
the last part of a pattern), and BN-X1..X3 passed on zero examples; only a count guard failed.

| Loop | Guard |
|---|---|
| guide examples (BN-X1..X3) | `good >= 5`, `bad >= 1` (was already there; it caught the defect) |
| BN-X5 skills | `skills > 0` (added) |
| BN-L1 `lints/check/bn_*.nim` | `seen == RuleId.high.ord + 1` (was already there) |
| BN-L2 `lints/check/cfg_*.nim` | `seen == settings` (was already there) |
| BN-L3 `src/**/*.nim` | `seen > 0` (added) |

No wildcard is left in a directory part of a pattern.

## Exit status read through a pipe (2026-11-19)

Found in the session that wrote the above, not in the repository: `nim test | grep | tail` gives
`tail`'s status. Population in the repository: 0 (CI runs `nim test` with no pipe).

## A finding placed in a file it was not found in (2026-11-19)

Found by review: with `--typed`, a public routine written in an `include`d file was reported with
its line and column but under the including file's name, pointing at unrelated code.

Population: findings are made in two places. `analyze.nim` reads one source, so every position is
in that source. `typed.nim` reads symbols of the whole module: the one case. Fixed by keeping only
symbols written in the checked file (BN-T1); the include itself is BN-06.
