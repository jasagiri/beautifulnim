# BeautifulNim

Agent skills that teach coding agents to write, review and port idiomatic Nim, a tested set of
compiler settings, and a small checker for the rules a parser can decide. Modelled on
[BeautifulRust](https://github.com/morganlinton/BeautifulRust).

| Path | What it is |
|---|---|
| `skills/nim-best-practices/` | The guide: 13 sections from mindset to a final checklist; source digests in `references/` |
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
2 usage error or a file that is not valid Nim.

| ID | Rule | Level |
|---|---|---|
| BN-01 | an `except` that only `discard`s | error |
| BN-02 | a `bool` parameter on a public routine | warning |
| BN-03 | a `converter` | error |
| BN-04 | warnings or hints switched off by a pragma | error |
| BN-05 | NEP1 naming (a public `getFoo` getter is info) | warning |
| BN-06 | `include` | warning |
| BN-07 | `method` | info |

`object of Exception` is not repeated: the compiler reports it (`InheritFromException`), and
`lints/nim.cfg` makes that an error. Everything else in the guide (ownership, `ref` only with a
reason, `Option` instead of sentinels, effects, concurrency, FFI soundness) is for people and agents
to judge; `nim-review` says how.

To embed the checker, `import beautifulnim` and add `--path:"$nim"` so that `compiler/` is found:

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
nim test     # rules, the command, every lints/nim.cfg setting, and every example in the guides
nim build
```

Every ```` ```nim ```` block in the skills must pass `nim check` under `lints/nim.cfg` and have no
findings at warning or above; ```` ```nim bad ```` blocks show mistakes and only have to parse.

## Sources

| Source | Version read | Licence | Used for |
|---|---|---|---|
| [NEP1](https://nim-lang.org/docs/nep1.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | naming, layout |
| [Nim manual](https://nim-lang.org/docs/manual.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | effects, types, exceptions |
| [Destructors and move semantics](https://nim-lang.org/docs/destructors.html) | Nim 2.4.2 docs | none on the page (Nim repository: MIT) | ownership, hooks |
| [Status Nim style guide](https://status-im.github.io/nim-style-guide/) | read 2026-11-17 | none found | production practices |

The digests in `skills/nim-best-practices/references/` paraphrase and say which chapters were read.
Where the sources disagree (`result`, constructor naming, the `Ref` suffix), the guide picks one and
says why.

## Licence

Apache-2.0 (`LICENSE`, `NOTICE`).
