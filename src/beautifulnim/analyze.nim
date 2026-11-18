## Checks Nim source against the rules in `rules.nim` (docs/specification.md).
##
## The tree comes from Nim's own parser (`compiler/parser.parseString`), so string literals
## and comments are never mistaken for code (ADR-BNIM-0001). Only the syntax is read:
## nothing is type-checked, so a rule sees names, not what they resolve to.

import std/strutils
import compiler/[ast, idents, lineinfos, options, parser]
import ./rules

const MaxSourceBytes* = 1 shl 20 ## larger input is refused before parsing (BN-P3)

type
  Finding* = object
    rule*: RuleId
    level*: Level
    line*, col*: int ## 1-based
    title*, fix*, section*: string

  ParseError* = object
    line*, col*: int ## 1-based; 0 when the parser gave no place
    message*: string

  Analysis* = object
    ok*: bool ## false when the source could not be parsed; findings are then empty
    findings*: seq[Finding]
    parseErrors*: seq[ParseError]

  ErrorSink = ref object
    errors: seq[ParseError]

const
  RoutineDefs = {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkTemplateDef,
                 nkMacroDef, nkConverterDef}
  ForeignNamePragmas = ["importc", "importcpp", "importjs", "importobjc", "exportc"]
  CodeFromString = ["parseStmt", "parseExpr"]
  ## Calls whose argument is only looked at, never run: a template argument inside them is
  ## not evaluated again (BN-10).
  NotEvaluating = ["typeof", "type", "compiles", "declared", "defined", "sizeof", "alignof",
                   "astToStr", "is", "isnot", "runnableExamples"]

proc isIdent(n: PNode; name: string): bool =
  n.kind == nkIdent and cmpIgnoreStyle(n.ident.s, name) == 0

func initFinding*(rule: RuleId; line, col: int; level = Rules[rule].level): Finding =
  ## A finding of `rule` at a 1-based place, with the rule's title, fix and section.
  let r = Rules[rule]
  Finding(rule: rule, level: level, line: line, col: col, title: r.title, fix: r.fix,
          section: r.section)

proc add(a: var Analysis; rule: RuleId; n: PNode; level = Rules[rule].level) =
  a.findings.add initFinding(rule, int(n.info.line), int(n.info.col) + 1, level)

proc nameNode(n: PNode): PNode =
  ## The identifier inside `name`, `name*`, `name {.p.}` or `name* {.p.}`.
  case n.kind
  of nkPostfix: nameNode(n[1])
  of nkPragmaExpr: nameNode(n[0])
  else: n

proc isExported(n: PNode): bool =
  case n.kind
  of nkPostfix: true
  of nkPragmaExpr: isExported(n[0])
  else: false

proc hasForeignName(pragmas: PNode): bool =
  if pragmas.kind != nkPragma: return false
  for p in pragmas:
    let key = if p.kind in {nkExprColonExpr, nkCall}: p[0] else: p
    for name in ForeignNamePragmas:
      if key.isIdent(name): return true
  false

proc onlyDiscards(body: PNode): bool =
  case body.kind
  of nkDiscardStmt: true
  of nkStmtList, nkStmtListExpr: body.len == 1 and onlyDiscards(body[0])
  else: false

proc isBoolType(t: PNode): bool =
  t.isIdent("bool") or (t.kind == nkVarTy and t.len == 1 and t[0].isIdent("bool"))

proc checkNaming(a: var Analysis; def: PNode) =
  ## BN-05 for a routine definition.
  let name = nameNode(def[namePos])
  if name.kind != nkIdent or hasForeignName(def[pragmasPos]): return
  let s = name.ident.s
  if s.len == 0 or s[0] notin Letters: return # operators
  if s[0] in UppercaseLetters or '_' in s:
    a.add(bn05Naming, name)
    return
  let params = def[paramsPos]
  if isExported(def[namePos]) and s.len > 3 and s.startsWith("get") and s[3] in UppercaseLetters and
      params.kind == nkFormalParams and params[0].kind != nkEmpty:
    var count = 0
    for i in 1 ..< params.len:
      if params[i].kind == nkIdentDefs: count += params[i].len - 2
    if count == 1: a.add(bn05Naming, name, lvInfo)

proc hasPragma(pragmas: PNode; name: string): bool =
  if pragmas.kind != nkPragma: return false
  for p in pragmas:
    if p.isIdent(name): return true
  false

proc isAnyIdent(n: PNode; names: openArray[string]): bool =
  for name in names:
    if n.isIdent(name): return true
  false

proc declares(n: PNode; name: string): bool =
  ## Whether `name` is declared (var, let, const, for, a routine or type name) anywhere in `n`;
  ## a template parameter used that way names a binding, it is not an expression.
  case n.kind
  of nkIdentDefs, nkVarTuple:
    for i in 0 ..< n.len - 2:
      if nameNode(n[i]).isIdent(name): return true
  of nkForStmt:
    for i in 0 ..< n.len - 2:
      if nameNode(n[i]).isIdent(name): return true
  of RoutineDefs, nkTypeDef:
    if nameNode(n[0]).isIdent(name): return true
  else: discard
  if n.kind notin {nkNone .. nkNilLit}:
    for son in n:
      if declares(son, name): return true
  false

proc uses(n: PNode; name: string): int =
  ## How many times the identifier `name` is evaluated in `n` on one run through it: the
  ## branches of if, when and case count as the largest one, and names that are only looked at
  ## (field names after a dot, inside typeof or astToStr) do not count.
  case n.kind
  of nkIdent: (if n.isIdent(name): 1 else: 0)
  of nkNone, nkEmpty, nkSym, nkType, nkCharLit .. nkNilLit: 0
  of nkDotExpr: uses(n[0], name)
  of nkBindStmt, nkMixinStmt: 0
  of nkExprColonExpr, nkExprEqExpr: uses(n[1], name)
  of nkCall, nkCommand, nkInfix, nkPrefix, nkCallStrLit:
    if n.len > 0 and n[0].isAnyIdent(NotEvaluating): 0
    else:
      var total = 0
      for son in n: total += uses(son, name)
      total
  of nkWhenStmt:
    # the conditions are compile-time constants; only the chosen branch is run
    var widest = 0
    for branch in n:
      if branch.len > 0: widest = max(widest, uses(branch[^1], name))
    widest
  of nkIfStmt, nkIfExpr:
    # reaching a branch evaluates the conditions of every branch before it
    var before = 0
    var widest = 0
    for branch in n:
      widest = max(widest, before + uses(branch, name))
      if branch.kind in {nkElifBranch, nkElifExpr}: before += uses(branch[0], name)
    widest
  of nkCaseStmt:
    # the selector runs once; `of` values are constants
    var widest = 0
    for i in 1 ..< n.len:
      if n[i].len > 0: widest = max(widest, uses(n[i][^1], name))
    uses(n[0], name) + widest
  else:
    var total = 0
    for son in n: total += uses(son, name)
    total

proc isRepeatSafe(t: PNode): bool =
  ## Parameter types whose repeated use evaluates nothing: types, compile-time values, var.
  t.isIdent("typedesc") or t.kind == nkVarTy or t.kind == nkStaticTy or
    (t.kind == nkBracketExpr and t.len > 0 and t[0].isAnyIdent(["typedesc", "static"])) or
    (t.kind == nkCommand and t.len > 0 and t[0].isIdent("static"))

proc checkTemplate(a: var Analysis; def: PNode) =
  ## BN-08 and BN-10.
  if hasPragma(def[pragmasPos], "dirty"):
    a.add(bn08DirtyTemplate, def)
  let params = def[paramsPos]
  if params.kind != nkFormalParams: return
  let body = def[bodyPos]
  for i in 1 ..< params.len:
    let defs = params[i]
    if defs.kind != nkIdentDefs or isRepeatSafe(defs[^2]): continue
    for j in 0 ..< defs.len - 2:
      let p = defs[j]
      if p.kind != nkIdent or declares(body, p.ident.s): continue
      if uses(body, p.ident.s) > 1:
        # a caller of a public template cannot see the body; a private one is its author
        a.add(bn10RepeatedTemplateArg, p, if isExported(def[namePos]): lvWarning else: lvInfo)

proc checkRoutine(a: var Analysis; def: PNode) =
  case def.kind
  of nkConverterDef: a.add(bn03Converter, def)
  of nkMethodDef: a.add(bn07Method, def)
  of nkTemplateDef: checkTemplate(a, def)
  else: discard
  checkNaming(a, def)
  let params = def[paramsPos]
  if isExported(def[namePos]) and params.kind == nkFormalParams:
    for i in 1 ..< params.len:
      let defs = params[i]
      if defs.kind == nkIdentDefs and isBoolType(defs[^2]):
        for j in 0 ..< defs.len - 2: a.add(bn02PublicBoolParam, defs[j])

proc checkTypeDef(a: var Analysis; def: PNode) =
  let name = nameNode(def[0])
  let pragmas = if def[0].kind == nkPragmaExpr: def[0][1] else: newNode(nkEmpty)
  if name.kind == nkIdent and not hasForeignName(pragmas):
    let s = name.ident.s
    if s.len > 0 and (s[0] in LowercaseLetters or '_' in s):
      a.add(bn05Naming, name)

proc checkPragma(a: var Analysis; pragma: PNode) =
  for p in pragma:
    if p.kind != nkExprColonExpr or not p[1].isIdent("off"): continue
    let key = if p[0].kind == nkBracketExpr: p[0][0] else: p[0]
    for name in ["warnings", "warning", "hints", "hint"]:
      if key.isIdent(name):
        a.add(bn04SilencedWarning, p)
        break

proc walk(a: var Analysis; n: PNode) =
  case n.kind
  of nkExceptBranch:
    if n.len > 0 and onlyDiscards(n[^1]): a.add(bn01EmptyExcept, n)
  of RoutineDefs: checkRoutine(a, n)
  of nkTypeDef: checkTypeDef(a, n)
  of nkPragma: checkPragma(a, n)
  of nkIncludeStmt: a.add(bn06Include, n)
  of nkCall, nkCommand, nkCallStrLit:
    if n.len > 0 and n[0].isAnyIdent(CodeFromString): a.add(bn09CodeFromString, n)
  of nkDotExpr:
    if n[1].isAnyIdent(CodeFromString): a.add(bn09CodeFromString, n)
  else: discard
  if n.kind notin {nkNone .. nkNilLit}: # leaves have no sons
    for son in n: walk(a, son)

proc parse(source: string; sink: ErrorSink): PNode {.raises: [].} =
  let conf = newConfigRef()
  conf.errorMax = high(int) # keep going after the first error so every message is collected
  conf.m.errorOutputs = {} # messages reach `sink` through the structured hook, not the console
  conf.structuredErrorHook = proc (config: ConfigRef; info: TLineInfo; msg: string;
                                   level: Severity) {.closure, gcsafe.} =
    if level == Severity.Error:
      sink.errors.add ParseError(line: int(info.line), col: int(info.col) + 1, message: msg)
  try:
    parseString(source, newIdentCache(), conf)
  except Exception as e:
    # The compiler's modules carry no raises annotations, so the call is inferred to raise
    # Exception. Whatever it raises is reported as a parse error, not dropped.
    sink.errors.add ParseError(message: "the parser failed: " & e.msg)
    nil

proc analyze*(source: string): Analysis {.raises: [].} =
  ## Parses `source` and returns every finding, or the parse errors when it does not parse.
  if source.len > MaxSourceBytes:
    return Analysis(ok: false, parseErrors: @[ParseError(
      message: "source is " & $source.len & " bytes, over MaxSourceBytes (" & $MaxSourceBytes & ")")])
  let sink = ErrorSink()
  let tree = parse(source, sink)
  if tree.isNil or sink.errors.len > 0:
    return Analysis(ok: false, parseErrors: sink.errors)
  result = Analysis(ok: true)
  walk(result, tree)
