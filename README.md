# BeautifulNim

Agent skills that teach coding agents to write, review and port idiomatic Nim, a tested set of
compiler settings, and a small checker for the rules a parser can decide. Modelled on
[BeautifulRust](https://github.com/morganlinton/BeautifulRust).

| Path | What it is |
|---|---|
| `skills/nim-best-practices/` | The guide: section 0 on conflicts with the task, then 13 sections from mindset to a final checklist; parts read only for some code in `details/`; source digests in `references/` |
| `skills/nim-review/` | Reviewing Nim code: scope, tools first, reading order, a Must / Should / Consider report |
| `skills/nim-port/` | Porting C, C++, Python, Rust, Go, JavaScript or TypeScript to Nim, tests first |
| `lints/nim.cfg` | Compiler settings that turn bug-shaped warnings into errors |
| `src/beautifulnim/` | The checker (library and the `beautifulnim` command) |
| `docs/specification.md` | What every rule and option does; the tests are named after these IDs |

The skills use the [Agent Skills](https://agentskills.io) format (`SKILL.md` with `name` and
`description`). For Claude Code, copy or link the three directories into `~/.claude/skills/` (or a
project's `.claude/skills/`).

## The checker

```sh
nimble install            # or: nimble build
beautifulnim check src/*.nim
beautifulnim check --min-level:warning --format:json src/foo.nim
beautifulnim rules
```

It reads code with Nim's own parser (`compiler/parser`, shipped with Nim), so text in strings and
comments never matches (docs/adr/ADR-BNIM-0001). Exit status: 0 nothing to report, 1 findings,
2 usage error, a file that is not valid Nim or, with `--typed`, a file that does not compile.

`--typed` checks each file as `nim check` does (its `nim.cfg` and `config.nims` apply, imports are
resolved) and decides BN-02 on the resolved types, so `type Flag = bool` counts as `bool` and
`distinct bool` does not (docs/adr/ADR-BNIM-0003). It also reports BN-11, a type with its own
`=destroy` and no `=copy`, from the hooks the compiler bound to the type (docs/adr/ADR-BNIM-0004),
BN-12, a returned `cstring` of a temporary, local or `sink` string (docs/adr/ADR-BNIM-0006), and drops BN-05 findings
the symbols show to be wrong: names under `{.push importc.}` or a `{.pragma.}` alias of `importc`, and
`getFoo` routines whose parameter is not an object or tuple (docs/adr/ADR-BNIM-0005). It takes as long as `nim check`, and it uses the
standard library of the Nim that built the checker: rebuild the checker after changing Nim. Like
`nim check`, it runs the file's compile-time code and its `config.nims`, so check only code you
would compile.

| ID | Rule | Level |
|---|---|---|
| BN-01 | an `except` that only `discard`s | error |
| BN-02 | a `bool` parameter on a public routine (behind an alias too, with `--typed`) | warning |
| BN-03 | a `converter` | error |
| BN-04 | warnings or hints switched off by a pragma | error |
| BN-05 | NEP1 naming (a public `getFoo` getter is info) | warning |
| BN-06 | `include` | warning |
| BN-07 | `method` | info |
| BN-08 | a `{.dirty.}` template (hygiene off) | warning |
| BN-09 | code built from a string with `parseStmt`/`parseExpr` | warning |
| BN-10 | a template argument evaluated more than once (info on private templates) | warning |
| BN-11 | a type with `=destroy` and no `=copy`, so a copy frees twice (`--typed` only) | error |
| BN-12 | a returned `cstring` of a string freed on return (`--typed` only) | error |

`object of Exception` is not repeated: the compiler reports it (`InheritFromException`), and
`lints/nim.cfg` makes that an error. Everything else in the guide (ownership beyond BN-11, `ref` only with a
reason, `Option` instead of sentinels, effects, concurrency, FFI soundness) is for people and agents
to judge; `nim-review` says how.

To embed the checker, `import beautifulnim` and add `--path:"$nim"` so that `compiler/` is found
(`import beautifulnim/typed` for `analyzeTyped` also needs `-d:nimcore`):

```nim
import beautifulnim
let a = analyze(readFile("foo.nim"))
for f in a.findings.atOrAbove(lvWarning):
  echo textLine("foo.nim", f)
```

## Compiler settings

Copy the lines of `lints/nim.cfg` into your project's `nim.cfg`. Each one has a file in
`lints/check/` that it must reject, and the tests make sure it does. `BareExcept`
(`except Exception:`) is deliberately absent: `std/unittest`'s own templates trigger it, so as an
error it would fail every test that imports unittest. The guide still forbids it.

## Development

```sh
nim test     # rules, the command (with --typed), every lints/nim.cfg setting, and every example in the guides
nim build
```

CI (`.github/workflows/test.yml`) runs `nim test` on Linux, macOS and Windows.

Every ```` ```nim ```` block in the skills must pass `nim check` under `lints/nim.cfg` and have no
findings at warning or above; ```` ```nim bad ```` blocks show mistakes and only have to parse.

## Sources

| Source | Version read | Licence | Used for |
|---|---|---|---|
| [NEP1](https://nim-lang.org/docs/nep1.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | naming, layout |
| [Nim manual](https://nim-lang.org/docs/manual.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | effects, types, exceptions, templates, macros |
| [Destructors and move semantics](https://nim-lang.org/docs/destructors.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | ownership, hooks |
| [Status Nim style guide](https://status-im.github.io/nim-style-guide/) | read 2026-11-17 | none found | production practices |
| [On Lisp](https://paulgraham.com/onlisptext.html), Paul Graham | author's digital edition, ch. 8 and 10 | © the author, free digital edition; short quotes only | when a macro is justified, evaluation count and order |
| [Google Common Lisp Style Guide](https://google.github.io/styleguide/lispguide.html) | read 2026-11-17, section Macros | CC-BY 3.0 | hygiene, once-only, call-with style |

The digests in `skills/nim-best-practices/references/` paraphrase and say which chapters were read.
Where the sources disagree (`result`, constructor naming, the `Ref` suffix), the guide picks one and
says why.

## Licence

Apache-2.0 (`LICENSE`, `NOTICE`).
