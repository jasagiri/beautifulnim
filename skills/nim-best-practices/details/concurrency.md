# Concurrency and async

Part of nim-best-practices section 7. Read it before writing threads, locks, channels or async
code.

- Threads are on by default in Nim 2. Move data between threads instead of sharing it:
  `Isolated[T]` (std/isolation) proves a value has no other references; channels pass ownership.
- A thread proc must be `gcsafe`: no access to globals holding `string`, `seq`, `ref` or closures.
  Do not silence that with `{.cast(gcsafe).}`; restructure, or explain in a comment why the access
  is safe and how it is synchronised. The one common exception: a global marked
  `{.guard: lock.}` is still not GC-safe inside `withLock`, so put `{.cast(gcsafe).}` inside the
  `withLock` block, around the guarded access only, with a comment naming the lock.
- Shared state: one `Lock` per invariant, fields marked `{.guard: lock.}` so the compiler enforces
  `withLock`, short critical sections, and no callbacks or I/O while holding a lock.
- Async: use one runtime per program — `std/asyncdispatch` or `chronos` — and follow the project.
  `await` every future or handle it; `asyncCheck` turns a failure into a crash of the dispatcher.
  `std/asyncdispatch` futures carry no exception types, so a proc that calls `await`, `waitFor`
  or `asyncCheck` is inferred to raise `Exception`. Handle the failure where the future completes
  (`try`/`except` around `await` inside the async proc), and write `{.raises: [Exception].}` on
  the synchronous caller with a comment saying why. On an exported proc that annotation is the
  one section 5 asks for, and it is required: the compiler checks it, and a narrower list does
  not compile.
  CPU-bound work blocks the event loop; give it a thread pool.
- Libraries do not start threads or run the event loop; they take what they need as parameters.
