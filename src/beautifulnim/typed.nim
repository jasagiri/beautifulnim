## `beautifulnim check --typed`: the rules of `analyze.nim`, with BN-02 decided on the types the
## compiler resolves instead of the names written (docs/specification.md BN-T, ADR-BNIM-0003).
##
## The file is checked the way `nim check` checks it: the nim.cfg and config.nims files that
## `nim check` would read apply, and imports are resolved. The standard library used is the one of
## the Nim that built this checker, because the compiler modules compiled into it must match it.
## Importing this module compiles Nim's semantic checker into the program; `import beautifulnim`
## alone does not.

when not defined(nimcore):
  {.error: "beautifulnim/typed needs -d:nimcore: without it the compiler's VM does not register " &
    "compile-time procs such as querySetting, and checking code that calls them fails".}

import std/[algorithm, compilesettings, os]
import compiler/[ast, cmdlinehelper, commands, condsyms, idents, lineinfos, modulegraphs,
                 msgs, options, pathutils, pipelines]
import ./[analyze, rules]

type
  CompileError* = object
    file*: string ## the checked file as given, or the full path of an imported file; "" when unknown
    line*, col*: int ## 1-based; 0 when the compiler gave no place
    message*: string

  TypedAnalysis* = object
    ok*: bool ## false when the file cannot be read, does not parse or does not compile; findings are then empty
    readError*: string ## why the file could not be read; "" when it was read
    findings*: seq[Finding] ## ordered by line, then column
    errors*: seq[CompileError]

  ErrorSink = ref object
    errors: seq[CompileError]

const
  Routines = {skProc, skFunc, skMethod, skIterator, skTemplate, skMacro, skConverter}
  ## What a parameter's type is written through without changing what it is.
  Transparent = {tyVar, tySink, tyAlias, tyGenericInst}

let builtWithStdlib* = querySetting(libPath)
  ## The standard library of the Nim that built this program; the compiler modules compiled into
  ## it match that library and no other.

proc errorFile(conf: ConfigRef; info: TLineInfo; path: string): string =
  if info.fileIndex == InvalidFileIdx: ""
  elif info.fileIndex == conf.projectMainIdx: path
  else: toFullPath(conf, info)

proc semCheck(path, stdlib: string; sink: ErrorSink): seq[Finding] =
  ## Runs the compiler's semantic pass on `path` as the main module and returns a BN-02 finding
  ## for each parameter of type bool of each public routine declared in it.
  let cache = newIdentCache()
  let conf = newConfigRef()
  let prog = NimProg(suggestMode: true,
    processCmdLine: proc (pass: TCmdLinePass; cmd: string; conf: ConfigRef) =
      if pass == passCmd1: conf.projectName = path)
  prog.initDefinesProg(conf, "beautifulnim")
  prog.processCmdLineAndProjectPath(conf)
  conf.prefixDir = AbsoluteDir(stdlib.parentDir)
  conf.writelnHook = proc (msg: string) = discard # errors arrive through the hook below
  conf.errorMax = high(int) # collect every error, not only the first
  conf.structuredErrorHook = proc (config: ConfigRef; info: TLineInfo; msg: string;
                                   level: Severity) {.closure, gcsafe.} =
    # Inside compiles() and similar trials errorOutputs is {}: those errors are expected.
    if level == Severity.Error and config.m.errorOutputs != {}:
      let e = CompileError(file: errorFile(config, info, path), line: int(info.line),
        col: (if info.line == 0: 0 else: int(info.col) + 1), message: msg)
      # the compiler reports some errors twice at the same place with the same text
      if e notin sink.errors: sink.errors.add e
  let graph = newModuleGraph(cache, conf)
  if not prog.loadConfigsAndProcessCmdLine(cache, conf, graph):
    # In suggest mode the call returns false only after reporting an error through the hook.
    return
  # A .nims file is checked as NimScript, as `nim check foo.nims` does (loadConfigsAndProcessCmdLine
  # sets optWasNimscript); its system module is compiled for the VM and breaks with ORC's defines.
  if conf.selectedGC == gcUnselected and optWasNimscript notin conf.globalOptions:
    initOrcDefines(conf)
  setPipeLinePass(graph, SemPass)
  conf.setCmd cmdCheck
  defineSymbol(conf.symbols, $conf.backend)
  conf.searchPaths.add conf.libpath
  compilePipelineProject(graph)
  if sink.errors.len > 0: return
  let module = graph.getModule(conf.projectMainIdx)
  if module.isNil:
    sink.errors.add CompileError(file: path, message: "the compiler did not produce a module")
    return
  for s in graph.allSyms(module):
    if s.kind notin Routines or sfExported notin s.flags or s.itemId.module != module.position or
        s.typ.isNil or s.typ.n.isNil:
      continue
    let params = s.typ.n
    for i in 1 ..< params.len:
      if params[i].kind != nkSym: continue
      let p = params[i].sym
      if p.typ != nil and p.typ.skipTypes(Transparent).kind == tyBool:
        result.add initFinding(bn02PublicBoolParam, int(p.info.line), int(p.info.col) + 1)

proc analyzeTyped*(path: string; stdlib = builtWithStdlib): TypedAnalysis {.raises: [].} =
  ## Checks the file at `path` with every rule; BN-02 on resolved types (BN-T1, BN-T2). The file is
  ## read here, not passed in, because the compiler reads it from disk too: both see the same file.
  ## A file that cannot be read, does not parse or does not compile gives its errors and no
  ## findings. `stdlib` must
  ## be the `lib` directory of the same Nim version as `builtWithStdlib` (for example after the
  ## installation moved); when it holds no `system.nim` nothing is checked (BN-T5).
  let source =
    try: readFile(path)
    except IOError as e:
      return TypedAnalysis(ok: false, readError: e.msg)
  let syntactic = analyze(source)
  if not syntactic.ok:
    result = TypedAnalysis(ok: false)
    for e in syntactic.parseErrors:
      result.errors.add CompileError(file: path, line: e.line, col: e.col, message: e.message)
    return
  if not fileExists(stdlib / "system.nim"):
    return TypedAnalysis(ok: false, errors: @[CompileError(file: path, message:
      "the Nim standard library this checker was built with is not at " & stdlib &
      "; rebuild beautifulnim with the Nim that should check the code")])
  let sink = ErrorSink()
  var typedBools: seq[Finding]
  try:
    typedBools = semCheck(path, stdlib, sink)
  except Exception as e:
    # The compiler's modules carry no raises annotations; whatever escapes is reported, not dropped.
    sink.errors.add CompileError(file: path, message: "the compiler failed: " & e.msg)
  if sink.errors.len > 0:
    return TypedAnalysis(ok: false, errors: sink.errors)
  result = TypedAnalysis(ok: true, findings: typedBools)
  for f in syntactic.findings:
    if f.rule != bn02PublicBoolParam: result.findings.add f
  result.findings.sort(proc (a, b: Finding): int =
    result = cmp(a.line, b.line)
    if result == 0: result = cmp(a.col, b.col))
