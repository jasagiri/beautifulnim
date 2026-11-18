# Templates and macros

Part of nim-best-practices section 4. Read it before writing a `template` or a `macro`.

A template pastes syntax trees at the call site; a macro is a proc the compiler runs on syntax
trees. Both are expanded into the caller's code, which is where their power and their bugs come
from. Lisp has lived with this for decades, and its lessons carry over almost unchanged
(`references/macros.md` maps them to Nim).

**Use the least powerful tool that works** (the manual's style note): a proc, then a generic
proc, then a template, then a macro. Speed is not a reason to climb: mark a small proc
`{.inline.}` instead (Google's Lisp guide: do not use macros for performance). Climb only for what a
proc cannot do (On Lisp, ch. 8):

- **Control evaluation**: run an argument lazily (only when logging is on), repeatedly (a body in
  a loop) or never (`astToStr`, `compiles`). A proc evaluates every argument exactly once, first.
- **Bind names the caller uses**: `withFile(f, …)` declares `f`; `mapIt` provides `it`.
- **Look inside an argument's syntax** (transformation): only a macro can see that an argument is
  `a == b` and report both sides. A template cannot take its argument apart.
- **Compute at compile time** what `const` and a proc called in a `const` cannot.

When you do climb, these hold:

1. **Stay hygienic (BN-08).** Templates are hygienic by default: a `let` or `var` inside one gets a
   fresh name and cannot clash with the caller's. Keep it that way. A name the caller must see
   comes in as a parameter or is marked `{.inject.}`, and the doc comment lists it. `{.dirty.}`
   switches hygiene off for every name in the template; keep it only with a comment saying why.
   Never read a caller's variable that is not a parameter: On Lisp calls such capture "a source of
   contagion" and notes that it usually happens by mistake.
2. **Evaluate each argument once, in order (BN-10).** A template pastes the argument's *tree* at
   every use, typed parameters included, so `sq(next())` with `x * x` in the body calls `next`
   twice. Bind each argument with `let` in the order the parameters appear, then use the binding.
   A literal (`nil`, `[]`, `{}`, `0`) has no side effects and may have no type of its own
   (`let r = nil` does not compile): paste it instead of binding it.
   The exceptions are the arguments the template exists to repeat or skip (a loop body, a lazily
   built message). Say so in the doc comment, so callers know.
3. **Build trees, not strings (BN-09).** In a macro, build code with `genAst` (std/genasts) or
   `quote do`. `parseStmt`/`parseExpr` on assembled text loses hygiene and the caller's line
   information. It also turns whatever reaches the string into code.
4. **A macro processes syntax; the work goes in procs.** Keep the expansion small. Have it call
   an ordinary proc that holds the logic, so that the logic is tested as a proc (Google's Lisp
   guide calls this "call-with style").
5. **Check the input's shape and report at the caller.** Before building anything, check the kind
   of each node (`expectKind`, `expectLen`, or an `if` with `error(msg, node)`). Then a misuse is one
   clear error on the caller's line, not a confusing one inside the expansion.
6. **`typed` before `untyped`.** Give a parameter a real type when it is a value: overloads resolve
   and type errors appear before expansion. Use `untyped` only for a name to bind, a body, or syntax
   to transform.
7. **Make it readable from outside.** Every public template and macro has a `##` comment that says
   what it expands to in words, which names it injects, and how often each argument is evaluated,
   plus `runnableExamples`: a code block in the routine's body right after the `##` lines, never
   text inside the comment (written there it is not compiled, and `nim doc` warns about broken
   links). Do not generate the public API with macros: it cannot be found by
   reading or documented (Status). Avoid macros that write macros (Google's Lisp guide).
8. **Say what control flow does inside a body.** A body parameter placed inside the template's
   own `while` or `for` captures the caller's `break` and `continue`: they leave your loop, not
   theirs, and nothing warns. `return` leaves the caller's proc. State in the doc comment which of
   these work. If `break` must reach the caller's loop, use a loop variable instead of a loop
   around the body. When repeating the body is the template's purpose (`retry`), the loop stays:
   document that `break` and `continue` end the template's loop, and leave it on a flag
   (`while not done`) rather than a `break` after the body: inside the loop,
   `try: done = true; body` and `except: done = false` (re-raise on the last attempt), so a body
   that finishes normally ends the loop and one that raises repeats it. Do not put statements after the body
   in the same block either: when the
   body always ends in `return` or `raise`, the caller gets an `UnreachableCode` warning for code
   they never wrote. Set a flag before the body instead (`done = true; body`) and clear it in the
   `except` branch. A warning about the caller's own statements after the template, when the
   body always returns, is correct: that code is dead, and it is the caller's to remove.
9. **Keep helpers private.** The proc that an expansion calls (rule 4) can stay unexported:
   templates and `genAst`/`quote` bind the symbols visible where they are defined. Exporting it
   would only add to the caller's namespace. Test the expansion from another module to be sure.
10. **Test the behaviour and the misuse.** Test what the expansion does, as you would a proc. Test
   rejected input with `doAssert not compiles(...)`. To see an expansion, use `expandMacros` or
   `echo result.repr` while writing the macro, and remove it before you hand the code back.

```nim bad
template sq*(x: int): int = x * x # sq(next()) calls next twice (BN-10); a proc would do
```

```nim
func sq*(x: int): int {.inline.} = x * x # a proc evaluates x once; inline keeps it fast

const debugLog {.booldefine.} = false

template debug*(msg: string) =
  ## Writes `msg` to stderr when compiled with `-d:debugLog`. `msg` is evaluated only then,
  ## so building it costs nothing in a normal build.
  when debugLog:
    stderr.writeLine msg
```

A macro that needs to see inside its argument checks the argument's shape, evaluates each operand
once, and builds the result with `genAst`. The example prints operands with `$`. When the operand
types are arbitrary, call a helper that falls back to `repr` (`when compiles($x): $x else: repr(x)`),
so that types without `$` still compile:

```nim
import std/[macros, genasts]

macro expect*(cond: untyped): untyped =
  ## Like `doAssert`, but a failed comparison shows both operands. Each operand is evaluated once,
  ## left to right; the names `l` and `r` are hygienic and cannot clash with the caller's.
  runnableExamples:
    let a = 2
    expect a + 1 == 3
    doAssert not compiles(expect true)
    doAssertRaises(AssertionDefect): expect a == 3
  const comparisons = ["==", "!=", "<", "<=", ">", ">="]
  if cond.kind != nnkInfix or cond[0].strVal notin comparisons:
    error("expect needs a comparison such as `a == b`", cond)
  let text = cond.repr
  result = genAst(op = cond[0], lhs = cond[1], rhs = cond[2], text):
    let l = lhs
    let r = rhs
    if not op(l, r):
      raiseAssert text & ": left is " & $l & ", right is " & $r
```
