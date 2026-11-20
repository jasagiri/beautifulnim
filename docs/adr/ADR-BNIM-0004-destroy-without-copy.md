# ADR-BNIM-0004: Report a type with `=destroy` and no `=copy` in `check --typed` (BN-11)

**ADR ID**: ADR-BNIM-0004
**Status**: accepted
**Date**: 2026-11-19
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

`skills/nim-best-practices/details/ownership.md` asks that a type with `=destroy` say what a copy
does. Without a `=copy` of its own, Nim 2.4.2 generates one that copies the fields, so the two
values release the same resource: a double free the first time a copy is made. The compiler gives
no warning, and `--expandArc` shows the generated `=copy` call [measured on Nim 2.4.2 and on
nimony master 18582911 (2026-10-23): both compile and run a copy of such a type silently].

ADR-BNIM-0003 left ownership out of `--typed`: "copies of types with `=destroy` … are decided after
semantic analysis, in the destructor injection pass, which `SemPass` does not run". That holds for
*where* a copy happens. *Whether a type has its own hooks* is known after semantic analysis: the
compiler binds a user hook to its type while checking the hook (`getAttachedOp`, flag
`sfOverridden`).

## Requirements

- A type declared in the checked file with a user `=destroy` and no user `=copy` is reported,
  public or private, generic or not.
- `=copy {.error.}` and a deep `=copy` both answer the question; neither is reported.
- A user `=dup` without `=copy` is reported: assigning to an existing variable still calls the
  generated `=copy` [measured with `--expandArc`: `b = a` becomes `\`=copy\`(b, a)`].
- One owner of "which hook belongs to which type": the compiler.

## Options

| Option | For | Against |
|---|---|---|
| A. Syntax rule: match `proc \`=destroy\`(x: T)` and `proc \`=copy\`(d: var T; …)` declarations by the type name written | no compiler, works without `--typed` | a second owner of hook binding; misses aliases, generic instances, hooks made by templates or macros |
| **B. Typed rule: after `SemPass`, read the type's attached `=destroy` and `=copy` and whether the user wrote them** | the compiler's own binding; no new pass | only with `--typed` (as slow as `nim check`) |
| C. Report each place a copy happens, by running destructor injection (`injectdestructors`) after `SemPass`, or by reading `--expandArc` | names the line of the copy | needs the transformation passes before injection; `--expandArc` is text per routine; adds little once B makes the type say what a copy does |
| D. Ask upstream for a compiler warning | every Nim user gets it | not in our hands; see "Not decided" |

## Trade-offs

The dominating axis is one owner of hook binding (as in ADR-BNIM-0003). A gives a second, partial
answer; C answers a different question (where) at a much higher cost, and with `=copy {.error.}`
`nim c` already reports each place [measured: "'=copy' is not available for type <Pool>; requires a
copy because it's not the last read of 'a'"]. B costs nothing beyond what `--typed` already pays.

## Decision

Option B. Rule BN-11 (level error, guide section 3), reported by `check --typed` only
(docs/specification.md BN-T6). The symbols are read from the module's full symbol table
(`semtabAll`), since `allSyms` yields only exported symbols.

## Consequences

- Without `--typed`, BN-11 is never reported; `beautifulnim rules` says so in the title.
- Where a copy happens is still not reported by beautifulnim. With `=copy {.error.}`, `nim c` names
  each place, but `nim check` does not: it stops before destructor injection [measured on 2.4.2].
- A type whose generated field-by-field copy is correct (its `=destroy` only logs, say) is reported;
  the guide asks such a type to write the copy it means anyway.

## Not decided

- Option C (where a copy happens) inside beautifulnim. Revisit if users of `=copy {.error.}` need the
  places from `nim check` rather than `nim c`.
- Upstream. Nimony is where new checks are taken first, and the stated plan is to backport Nimony
  features to Nim 2.x (forum, 2026-10-28). The path is: propose the warning for Nimony (its lifter,
  `src/hexer/lifter.nim`, generates the copy), and once Nimony has it, backport it to Nim 2.x as a
  warning (not an error, so valid code keeps compiling). The proposal and its schedule are tracked in
  nim-upstream-kit, not here. If either compiler gains the warning, BN-11 can defer to it for that
  compiler, as the rules already defer to compiler warnings (`lints/nim.cfg`).

## Rejected

- Option A: a second owner of hook binding, which the compiler already answers.

## 訂正 (2026-11-20)

RC-1: the decision read "a user `=destroy`" as the hook's `sfOverridden` flag alone. An alias
(`type D = string`) or a distinct type of `string` that is converted to reaches the `=destroy`
system declares for `string`, which carries that flag, and was reported as BN-11 at level error.
A type's hooks are written in the module of the type, so a hook counts only when it is declared in
the checked module (`userHook` in `src/beautifulnim/typed.nim`); docs/specification.md BN-T6
says so. Found by mutation testing of `typed.nim` on 2026-11-20.
