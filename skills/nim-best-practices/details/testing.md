# Fuzzing, memory tests, compile failures and specifications

Part of nim-best-practices section 11. Read it when the code parses untrusted input, owns memory
or calls C, must fail to compile in some use, or has a written specification.

- Fuzz parsers of untrusted input (anything the program does not control: user input, the
  network, files people edit such as configs): a seeded loop over random byte strings (say 100 000), where
  every input must give a result or the documented `CatchableError`; any `Defect` fails. Run tests
  under sanitizers
  (`-d:useMalloc --passC:-fsanitize=address --passL:-fsanitize=address --debugger:native`).
  Where the sanitizer cannot run (it fails to build, or a run hangs: give it a timeout), say so
  with the reason. Code that owns no memory needs nothing in its place; code that does is tested
  two other ways: build with `-d:useMalloc` so the platform allocator aborts on a double free (on macOS, also run with `MallocScribble=1`).
  Then, with the default allocator, compare `getOccupiedMem()` before and after a loop of
  create, move and destroy, at two loop counts (say 2 000 and 20 000). A difference that grows
  with the count is a leak. A constant one is the runtime's first-use allocation. These ownership
  tests are for code that owns memory (`ptr`, `alloc`, hooks); for code that does not, say so
  and skip them. Memory that C allocates (`strdup`, `malloc`) is invisible to `getOccupiedMem`:
  on macOS run the probe as `leaks --atExit -- ./probe` and expect `0 leaks`. For code whose only
  memory is what C allocates, `leaks` replaces the two ownership tests above.
- Test what must not compile. `doAssert not compiles(expr)` works for type errors and a macro's
  `error`, but not for a forbidden copy: `=copy {.error.}` is reported after `compiles` has
  answered (and after `nim check` has finished). Put the copy in its own file and expect `nim c` to fail.
- A written specification (a numbered rule, a table row) states one obligation per rule, in one
  sentence. Its values and examples live only in the tests that check it, so each is written
  once; a type (`distinct`, a constructor that validates) carries the rest. When the
  specification and a test say the same value, delete it from the specification.
