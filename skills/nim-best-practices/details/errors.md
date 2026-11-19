# Defect or CatchableError

Part of nim-best-practices section 5. Read it when a routine can fail on a value its caller
passes, to choose between a `Defect` and a `CatchableError`.

Ask who can prevent the failure.

- The caller can check it beforehand with what it already holds (an index below `len`, a
  non-empty `seq`, a call order): a precondition. Break it with a `Defect` (`IndexDefect`,
  `RangeDefect`, `AssertionDefect`) and name it in the `##` comment, as built-in indexing does.
- The caller cannot know beforehand (a file's contents, a network reply, a number read from a
  stream, the operating system's state): raise a `CatchableError` subtype and list it in `raises`.
- A public proc whose argument usually comes from outside (an offset a decoder reads from its
  input) counts as the second case even when a check is possible: callers will pass it unchecked.
  Either raise a `CatchableError`, or keep the `Defect` and add the check as its own proc
  (`contains`, `isValid`) that the doc comment tells callers to use first.
- Match the standard library's choice for the same kind of operation (`seq[i]`: `IndexDefect`;
  `Table[key]`: `KeyError`, a `CatchableError`).
