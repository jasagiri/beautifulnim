## The rules beautifulnim checks by machine. Each one points at the section of
## `skills/nim-best-practices/SKILL.md` that explains it; the rest of that guide is
## for people and agents to read, because a parser cannot judge it. A rule the compiler
## already reports (for example `object of Exception`, [InheritFromException]) is not repeated
## here; `lints/nim.cfg` turns those warnings into errors.

type
  RuleId* = enum
    bn01EmptyExcept = "BN-01"
    bn02PublicBoolParam = "BN-02"
    bn03Converter = "BN-03"
    bn04SilencedWarning = "BN-04"
    bn05Naming = "BN-05"
    bn06Include = "BN-06"
    bn07Method = "BN-07"
    bn08DirtyTemplate = "BN-08"
    bn09CodeFromString = "BN-09"
    bn10RepeatedTemplateArg = "BN-10"
    bn11DestroyWithoutCopy = "BN-11" ## needs the resolved types: reported by `check --typed` only
    bn12DanglingCstring = "BN-12" ## needs the resolved types: reported by `check --typed` only

  Level* = enum
    ## How sure the rule is that the code should change.
    lvError = "error"     ## the guide forbids it
    lvWarning = "warning" ## the guide asks for a reason when it is kept
    lvInfo = "info"       ## worth a look; often right as it is

  Rule* = object
    title*: string
    level*: Level
    section*: string ## the heading in skills/nim-best-practices/SKILL.md
    fix*: string

const Rules*: array[RuleId, Rule] = [
  bn01EmptyExcept: Rule(
    title: "an except branch that only discards the error",
    level: lvError,
    section: "5. Errors",
    fix: "propagate it, turn it into a value (Option or a result type), or log it with what failed"),
  bn02PublicBoolParam: Rule(
    title: "a public routine takes a bool parameter",
    level: lvWarning,
    section: "4. Types and API design",
    fix: "use a two-value enum, or two routines with names that say what each does"),
  bn03Converter: Rule(
    title: "a converter",
    level: lvError,
    section: "4. Types and API design",
    fix: "call an explicit conversion proc; converters silently erase the distinction a type draws"),
  bn04SilencedWarning: Rule(
    title: "a pragma that turns warnings off",
    level: lvError,
    section: "2. Before you hand back code",
    fix: "fix the cause the warning names; the warning is information"),
  bn05Naming: Rule(
    title: "a name that does not follow NEP1",
    level: lvWarning,
    section: "4. Types and API design",
    fix: "types are PascalCase, routines and variables camelCase without underscores, getters are named foo, not getFoo"),
  bn06Include: Rule(
    title: "an include statement",
    level: lvWarning,
    section: "9. Packages and modules",
    fix: "import the module; include pastes source and hides where names come from"),
  bn07Method: Rule(
    title: "a method (dynamic dispatch)",
    level: lvInfo,
    section: "4. Types and API design",
    fix: "prefer an object variant with case, a proc, or an object of closures, unless the set of types is open"),
  bn08DirtyTemplate: Rule(
    title: "a dirty template (hygiene switched off)",
    level: lvWarning,
    section: "4. Types and API design / Templates and macros",
    fix: "keep the template hygienic and mark only the names callers must see with {.inject.}"),
  bn09CodeFromString: Rule(
    title: "a macro builds code from a string (parseStmt or parseExpr)",
    level: lvWarning,
    section: "4. Types and API design / Templates and macros",
    fix: "build the tree with genAst or quote, so names stay hygienic and errors point at the caller"),
  bn10RepeatedTemplateArg: Rule(
    title: "a template uses an argument more than once, so the argument is evaluated more than once",
    level: lvWarning,
    section: "4. Types and API design / Templates and macros",
    fix: "make it a proc if it can be one; otherwise bind the argument once (let v = x) and use v, since a template pastes the argument, not its value"),
  bn11DestroyWithoutCopy: Rule(
    title: "a type with =destroy and no =copy, so a copy frees what it owns twice",
    level: lvError,
    section: "3. Values, copies and moves (ARC/ORC)",
    fix: "write =copy right after =destroy: {.error.} for a unique owner, a deep copy for a container (details/ownership.md)"),
  bn12DanglingCstring: Rule(
    title: "a returned cstring points into a string that is freed when the routine returns",
    level: lvError,
    section: "8. Unsafe code and FFI",
    fix: "return the string and convert at the call into C, or keep the string alive in the caller or a field (details/ffi.md)"),
]

const TypedOnly* = {bn11DestroyWithoutCopy, bn12DanglingCstring}
  ## Rules that need the types the compiler resolves; only `check --typed` (typed.nim) reports them.

proc parseLevel*(s: string): Level {.raises: [ValueError].} =
  ## "error", "warning" or "info".
  for l in Level:
    if $l == s: return l
  raise newException(ValueError, "level must be one of error, warning, info; got '" & s & "'")
