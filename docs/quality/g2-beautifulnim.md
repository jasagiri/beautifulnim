# G2 (mutation testing) — BeautifulNim

Measured 2026-11-20 with nim-muter 0.2.18, mutators AOR ROR LOR BLR SDL RVR LBR CVR, against the
E tests. Survivors are classified in the ledgers below; `nim-muter-ledger check <ledger>` exits 0
only when none is undecided, test_owed or spec_question.

| Scope (sources) | Tests run per mutant | Mutants (compile errors left out) | Killed | Survived | Ledger | check |
|---|---|---|---|---|---|---|
| `analyze.nim` | `test_analyze`, `test_lints`, `test_examples` | 228 | 209 | 19 | `survivors-analyze.json` | 0 |
| `report.nim`, `rules.nim` | `test_cli` | 4 | 4 | 0 | (in `survivors-analyze.json`, accepted, with the reason) | — |
| `cli.nim` | `test_cli` | 60 | 56 | 4 | `survivors-cli.json` | 0 |
| `typed.nim` | `test_typed`, `test_cli` | 158 | 144 | 14 | `survivors-typed.json` | 0 |

How the numbers came about:

- `analyze.nim`: 73.1% at first; the tests added in 23bd1946 brought it to 91.2%. The one
  spec_question (a parameter used as the type of a declaration counted as an evaluation for
  BN-10) was answered in the specification: a type is not evaluated. The changed lines were
  measured again: 209 of 228 (91.7%), one more mutant coming from the new branch of `uses`.
- `cli.nim`: 86.7% at first; dde9dea5 brought it to 93.3%. The 4 survivors are equivalent.
- `typed.nim`: 105 of 158 killed by `test_typed` alone (66.5%); `test_cli` killed 23 more. Of the
  30 left, the tests of 7739a5ab and of the commit after it killed 16, and the fix of BN-11 in
  6903400a came out of reading one (an alias of `string` was reported). The lines with survivors
  were measured again with both test files after the fix; the 14 left are 11 equivalent and 3
  unreached, each with its reason. Equivalence that rests on what the compiler produces was
  checked by building the mutant and running it on probe files, as the reasons say.
- `typed.nim`, after the BN-12 fix for block, if, case and try values (f99aa10a): its lines
  (`valuesOf` and `danglingCstrings`) were measured again with both test files: 42 of 44 killed.
  The 2 left are the same two equivalent mutants of the statement-list unwrapping as before, now
  in `valuesOf`; the ledger still has 14 survivors.

## Running it again

- With Xcode's license not accepted, the C compiler fails; `DEVELOPER_DIR=/Library/Developer/CommandLineTools`
  works around it.
- nim-muter puts its temporary directory inside the worker copy, so a parent `nim.cfg` reaches the
  files the tests write there. The tests pass `--skipParentCfg` to `nim check`; the `--typed`
  tests read parent configuration by design (BN-T3), so the test command sets `TMPDIR` to a fresh
  directory under `/tmp`:
  `export TMPDIR=$(mktemp -d /tmp/bnmut.XXXXXX) && ( nim c -r --hints:off tests/test_typed.nim && nim c -r --hints:off tests/test_cli.nim ); rc=$?; rm -rf "$TMPDIR"; exit $rc`
- One mutant of `typed.nim` takes 2 to 4 minutes (each run starts the compiler); restrict a run to
  the lines in question with `--lines src/beautifulnim/typed.nim:A-B`.
