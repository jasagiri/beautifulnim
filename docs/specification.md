# beautifulnim — specification

Each ID has E tests named after it (`tests/`). The check runs on the syntax tree that Nim's own
parser (`compiler/parser.parseString`) builds, so text inside string literals and comments never
matches a rule (ADR-BNIM-0001). What the compiler already reports (`object of Exception` is
[InheritFromException]) is not repeated; `lints/nim.cfg` makes such warnings errors (BN-L2).

## Rules (`src/beautifulnim/analyze.nim`, `rules.nim`)

| ID | Reports | Does not report |
|---|---|---|
| BN-01 | an `except` branch (bare or typed) whose body is only `discard` | a branch that does anything else (raise, log, return a value) |
| BN-02 | a public (`*`) proc, func, method, iterator, template or macro with a parameter of type `bool` | private routines; `bool` return types; a `var bool` out-parameter is still reported |
| BN-03 | every `converter` definition | — |
| BN-04 | a pragma that sets `warnings`, `warning[X]`, `hints` or `hint[X]` to `off`, alone or under `push` | the same keys set to `on` |
| BN-05 | a type name starting lowercase; a routine name starting uppercase or containing `_`; a type name containing `_`; a public routine `getFoo` with one parameter and a return type (level info) | declarations with `importc`, `importcpp`, `importjs` or `exportc` (they keep the foreign name); operators and backticked names |
| BN-06 | every `include` statement | — |
| BN-07 | every `method` definition (level info) | — |

Each finding carries the rule ID, level, 1-based line and column of the node, the rule's title,
the fix and the guide section.

## Input (`analyze`)

| ID | Input | Result |
|---|---|---|
| BN-P1 | source with a syntax error | `parseErrors` lists the parser's messages with line and column, `ok` is false; no exception escapes |
| BN-P2 | empty source | `ok`, no findings |
| BN-P3 | source longer than `MaxSourceBytes` (1 MiB) | `ok` is false with a parse error naming the limit; the parser is not run |

## Command (`src/beautifulnim/cli.nim`, `tests/test_cli.nim`)

| ID | Input | Result |
|---|---|---|
| BN-C1 | `beautifulnim check <files>` | one line per finding, `path:line:col: level: [BN-NN] title; fix`; exit 1 when there are findings, 0 when none |
| BN-C2 | `--min-level:error\|warning\|info` | only findings at that level or above are printed and counted for the exit status |
| BN-C3 | `--format:json` | a JSON array of `{"file", "findings": [{"rule", "level", "line", "col", "title", "fix", "section"}]}` |
| BN-C4 | a file that does not parse, or cannot be read | the parser's messages (or the read error) on stderr as `path:line:col: not valid Nim: …`; exit 2 |
| BN-C5 | no command, an unknown command or option, a bad level, `check` without files | the usage text; exit 2. `beautifulnim rules` lists every rule; exit 0 |

## Guide examples (`tests/test_examples.nim`)

| ID | Checks |
|---|---|
| BN-X1 | every ```` ```nim ```` block in `skills/*/SKILL.md` passes `nim check` on its own |
| BN-X2 | every ```` ```nim ```` block has no beautifulnim findings at level warning or above |
| BN-X3 | every ```` ```nim bad ```` block parses (it shows a mistake, so it may fail `nim check`) |

## Lint configuration (`lints/`)

| ID | Checks |
|---|---|
| BN-L1 | each `lints/check/bn_NN.nim` produces at least one finding of rule BN-NN |
| BN-L2 | each `lints/check/cfg_<name>.nim` fails `nim check` under `lints/nim.cfg` and passes without it |
| BN-L3 | the package's own `src/` has no findings |
