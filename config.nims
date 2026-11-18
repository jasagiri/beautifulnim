# Development tasks (`nim <task>`); listed at the end of `nim help`.
#
#   nim test    E tests (docs/specification.md)
#   nim build   the beautifulnim command
#
# Not nimble tasks: `test` and `build` clash with nimble's built-in commands.

task test, "E tests":
  for t in ["test_analyze", "test_cli", "test_typed", "test_lints", "test_examples"]:
    exec "nim c -r --hints:off tests/" & t & ".nim"

task build, "the beautifulnim command":
  exec "nim c -d:release --hints:off src/beautifulnim/cli.nim"
