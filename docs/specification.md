# beautifulnim — specification

Each ID has E tests named after it (`tests/`). The check runs on the syntax tree that Nim's own
parser (`compiler/parser.parseString`) builds, so text inside string literals and comments never
matches a rule (ADR-BNIM-0001). What the compiler already reports (`object of Exception` is
[InheritFromException]) is not repeated; `lints/nim.cfg` makes such warnings errors (BN-L2).

## Rules (`src/beautifulnim/analyze.nim`, `rules.nim`)

| ID | Reports | Does not report |
|---|---|---|
| BN-01 | an `except` branch (bare or typed) whose body is only `discard` | a branch that does anything else (raise, log, return a value) |
| BN-02 | a public (`*`) proc, func, method, iterator, template or macro with a parameter of type `bool`, once at each such parameter's name (`a, b: bool` gives two) | private routines; `bool` return types; a `var bool` out-parameter is still reported; a `bool` behind an alias (see BN-T1) |
| BN-03 | every `converter` definition | — |
| BN-04 | a pragma that sets `warnings`, `warning[X]`, `hints` or `hint[X]` to `off`, alone or under `push` | the same keys set to `on` |
| BN-05 | a type name starting lowercase; a routine name starting uppercase or containing `_`; a type name containing `_`; a public routine `getFoo` with one parameter and a return type (level info) | declarations with `importc`, `importcpp`, `importjs` or `exportc` (they keep the foreign name); operators and backticked names |
| BN-06 | every `include` statement | — |
| BN-07 | every `method` definition (level info) | — |
| BN-08 | a `template` with the `{.dirty.}` pragma | templates that mark single names `{.inject.}` |
| BN-09 | a call of `parseStmt` or `parseExpr`, plain, qualified (`macros.parseStmt`) or as a method call (`"…".parseExpr`), reported once | trees built with `quote` or `genAst` |
| BN-10 | a template parameter evaluated more than once in one run through the body: level warning on a public template, info on a private one | parameters of type `typedesc`, `static[T]` or `var T`; a parameter the body declares as a name (`var x`); uses in different branches of `if`/`case`/`when` (the costliest branch counts, with the conditions of the `if` branches before it; `case` `of` values and `when` conditions do not count); uses inside `typeof`, `type`, `compiles`, `declared`, `defined`, `sizeof`, `alignof`, `astToStr`, `is`, `isnot`, `runnableExamples`, `bind`, `mixin`; a name after a dot or before `:`/`=` in a constructor or named argument; procs |

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
| BN-C3 | `--format:json` | a JSON array with one entry per file, in order: `{"file", "findings": [{"rule", "level", "line", "col", "title", "fix", "section"}]}`, or, for a file that could not be checked (BN-C4, BN-C6), `{"file", "errors": [{"file", "line", "col", "kind", "message"}]}` with no `"findings"`, `kind` being `cannot read`, `not valid Nim` or `does not compile`; the messages also go to stderr and the exit is 2 |
| BN-C4 | a file that does not parse, or cannot be read (with or without `--typed`) | the parser's messages on stderr as `path:line:col: not valid Nim: …`, or `path: cannot read: …`; exit 2 |
| BN-C5 | no command, an unknown command or option, a bad level, `check` without files, `--typed` with a value | the usage text; exit 2. `beautifulnim rules` lists every rule; exit 0 |
| BN-C6 | `check --typed` on a file that parses but does not compile, or imports one that does not | the compiler's errors on stderr as `path:line:col: does not compile: …`, each once (an error in an imported file names that file; an error with no place names the checked file, with line and column 0); exit 2 |

## Typed check (`src/beautifulnim/typed.nim`, `check --typed`, ADR-BNIM-0003)

| ID | Input | Result |
|---|---|---|
| BN-T1 | a public proc, func, method, iterator, template, macro or converter written in the checked file whose parameter's type is `bool` after `var`, `sink`, aliases (`type Flag = bool`) and generic aliases (`type G[T] = bool`) are resolved | BN-02 at the parameter's name. Not reported: `distinct bool`, generic parameters, private routines, routines of imported modules, routines written in a file the checked file `include`s |
| BN-T2 | any file that compiles | every other rule is reported as without `--typed`; BN-02 comes only from BN-T1, so a plain `bool` is reported once; findings ordered by line, then column |
| BN-T3 | a file with `nim.cfg` or `config.nims` beside it or in a parent directory | they apply as they do for `nim check` (search paths, defines), to that file only when several files are checked in one run; the standard library is that of the Nim the checker was built with. Compile-time code runs as in `nim check`: `staticExec` and `writeFile` do nothing, and output printed at compile time is not shown |
| BN-T4 | a `.nims` file | checked as NimScript, as `nim check foo.nims` does (`switch` and the other NimScript procs resolve) |
| BN-T5 | `analyzeTyped(path)` with a `stdlib` directory that has no `system.nim` (by default `builtWithStdlib`, so after the Nim that built the checker was removed), or a `path` that cannot be read | `ok` is false with one error naming the directory and asking for a rebuild, or with `readError` set and no errors; the compiler is not run. The file is read by `analyzeTyped` itself, so the syntax rules and the compiler see the same file (`tests/test_typed.nim`) |

## Continuous integration (`.github/workflows/test.yml`)

`nim test` runs on Linux, macOS and Windows with Nim 2.4.2. Files are checked out with LF line ends
(`.gitattributes`), so BN-X4 counts the same characters everywhere.

## Guide examples (`tests/test_examples.nim`)

| ID | Checks |
|---|---|
| BN-X1 | every ```` ```nim ```` block in `skills/*/SKILL.md` and `skills/*/details/*.md` passes `nim check` on its own under `lints/nim.cfg`, and `nim doc` when it has `runnableExamples` |
| BN-X2 | every ```` ```nim ```` block has no beautifulnim findings at level warning or above |
| BN-X3 | every ```` ```nim bad ```` block parses (it shows a mistake, so it may fail `nim check`) |
| BN-X4 | `skills/nim-best-practices/SKILL.md` is at most 28 000 characters, so one read holds it (docs/adr/ADR-BNIM-0002) |
| BN-X5 | each skill's `SKILL.md` names every file in its `details/`, and every `details/*.md` it names exists |
| BN-X6 | the ```` ```nim ```` block in `README.md` (embedding the checker) passes `nim check` with `--path:src --path:"$nim"`, and `import beautifulnim` does not import `compiler/sem.nim` |

## Lint configuration (`lints/`)

| ID | Checks |
|---|---|
| BN-L1 | each `lints/check/bn_NN.nim` produces at least one finding of rule BN-NN |
| BN-L2 | each `lints/check/cfg_<name>.nim` fails `nim check` under `lints/nim.cfg` and passes without it |
| BN-L3 | the package's own `src/` has no findings |
