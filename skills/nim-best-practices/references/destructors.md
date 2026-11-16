# Nim destructors and move semantics (digest)

- Source: https://nim-lang.org/docs/destructors.html (documentation of Nim 2.4.2, read 2026-11-17).
  Author: Andreas Rumpf. The page states no licence; the Nim repository is MIT except where a module
  says otherwise. Paraphrased.

## Hooks

- ARC/ORC memory management is built on destructors; files and sockets need no manual close.
- Six hooks, bound statically: `=destroy`, `=wasMoved`, `=sink`, `=copy`, `=trace`, `=dup`.
- `=destroy` frees what the object owns; check for the moved-from state first. It is implicitly
  `{.raises: [].}`.
- `=wasMoved` resets an object so its destructor has nothing to do.
- `=sink` is rarely needed: providing `=destroy` and `=copy` is usually enough.
- `=copy` runs when an assignment cannot become a move; guard against self-assignment. Declaring it
  `{.error.}` forbids copies at compile time.
- `=trace` is only for custom containers under ORC whose manually allocated memory can hold cycles.
- Define a hook before the code that uses it.

## Moves

- A move is an optimised copy used when the source is not read again. `move` forces one;
  `ensureMove` fails to compile if a move cannot be proven.
- `sink T` parameters may consume the value; analysis is local; inference needs `--sinkInference:on`.
- `lent T` returns a borrowed view, the recommended form for getters.
- Object and array construction take their fields as sink parameters.

## Cursors

- `{.cursor.}` marks a non-owning `ref` to break cycles; it is a raw pointer, not a weak pointer.
- The compiler infers cursors for locals whose source is not mutated.
