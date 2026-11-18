# ADR-BNIM-0003: Decide BN-02 on resolved types behind `check --typed`

**ADR ID**: ADR-BNIM-0003
**Status**: accepted
**Date**: 2026-11-19
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

ADR-BNIM-0001 limits the checker to the syntax tree, so BN-02 sees the name `bool` and nothing
behind it: `type Flag = bool` followed by `proc open*(create: Flag)` is not reported, although
it is the same API mistake. ADR-BNIM-0001 left open whether to add checks that need name
resolution.

## Requirements

- A parameter whose type resolves to `bool` through aliases is reported by BN-02.
- A `distinct bool` is a new type that names its meaning; it is not reported.
- The file is resolved exactly as `nim check` resolves it: its `nim.cfg` and `config.nims`, its
  imports, the standard library. A checker that resolves imports differently from the compiler
  reports on code the compiler does not see.
- A file that does not compile is not checked; the compiler's errors are shown (as BN-C4 does for
  parse errors).
- Users who only want the syntax rules keep the current speed and behaviour.

## Options

| Option | For | Against |
|---|---|---|
| A. Keep syntax only, document the gap | nothing to build | the gap stays; an agent that hides a `bool` behind an alias passes |
| B. Resolve aliases declared in the same file by hand | fast, no compiler | a second owner of "what a type is"; misses aliases imported from other modules |
| C. Run `nim check` as a subprocess and parse its output | uses the user's compiler | `nim check` prints no types; would need `nim dump`/`--expandArc`-style output that does not exist for parameter types |
| **D. Run the compiler's semantic pass in-process** (`compiler/pipelines`, `SemPass`) and read the exported routine symbols of the main module | the compiler itself resolves names, imports and configs (`cmdlinehelper.loadConfigsAndProcessCmdLine`, as nimsuggest does) | the binary contains Nim's semantic checker (a debug build of `cli.nim` takes about 2 minutes instead of seconds); `compiler/` is an internal API; the standard library must be the one the checker was built with |

## Trade-offs

The dominating axis is "one owner of what a name means": B and C each add a second, partial answer
to a question the compiler already answers. D pays for that with build time and a tighter coupling
to the compiler version, which ADR-BNIM-0001 already accepted for the parser (`nim >= 2.4.2`,
checked by `nim test` before the requirement moves).

## Decision

Option D, behind an opt-in flag `beautifulnim check --typed` (`src/beautifulnim/typed.nim`).

- Without `--typed` nothing changes (ADR-BNIM-0001).
- With `--typed`, every rule except BN-02 still runs on the syntax tree; BN-02 is decided on the
  parameter symbols' types with `var`, `sink`, aliases and generic aliases resolved. One finding per parameter, in both modes, so the two modes agree on plain
  `bool`.
- The standard library used is `querySetting(libPath)` of the Nim that built the checker: the
  compiler modules compiled in must match it. If that directory is gone, the check stops with a
  message to rebuild; it does not look for another Nim.
- The compiler's VM registers compile-time procs (`querySetting`, `staticExec`...) only when built
  with `-d:nimcore`; the package's `nim.cfg` defines it and `typed.nim` refuses to compile
  without it.
- `import beautifulnim` does not import `typed.nim`, so embedding the syntax checker stays small.

## Consequences

- `nimble install` and `nim test` compile Nim's semantic checker (minutes, not seconds).
- `--typed` takes as long as `nim check` on the same file, per file.
- Compiler warnings are not reported by `--typed`; `lints/nim.cfg` and `nim check` own them.
- Ownership rules (copies of types with `=destroy`) are still not checked: they are decided after
  semantic analysis, in the destructor injection pass, which `SemPass` does not run.

## Not decided

- Whether other rules (BN-05 on symbol kinds, ownership through `--expandArc`) move to the typed
  pass.

## Rejected

- Making `--typed` the default: it would make every check as slow as `nim check` and fail on files
  that do not compile yet, which the syntax rules can still check.
