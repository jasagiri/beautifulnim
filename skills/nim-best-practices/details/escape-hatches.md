# When a check stops you

Part of nim-best-practices section 0. Read it when a compiler error, a failed effect check, a
forbidden copy or a run-time check (the length assertion of a `for` loop) stops you, and before handing back code that was ported or generated in bulk.

A check that stops you says the shape of the code is wrong for what the check guards: ownership,
effects, types. Change the shape. A change whose only purpose is to make the error go away (a
copy, a `ref`, a `cast`, a `cast` pragma, a macro) keeps the build green and moves the cost
somewhere no test looks: an allocation on every call, a second owner, an effect that still happens.
Such a change is a finding even when everything compiles and every test passes. In your notes,
name each check that stopped you and the shape you changed.

| The check | The shortcut that compiles | What it costs | The shape to use instead |
|---|---|---|---|
| `=copy {.error.}`, or a value passed to `sink` and used again | copy it: a deep `=copy`, `deepCopy`, a second variable | an allocation per call; two values that each think they own the data | move at the last use (`move x`), borrow with a plain parameter, return a view with `lent T`, or keep one owner and hand out indices |
| mutate one element while reading another, or a `var` parameter that aliases | wrap the data in `ref`, or a module-level `var` | reference counting on every access, unclear ownership, global state, cycles for ORC | one owner holds the `seq`; others hold an index into it; read in one loop, collect the changes, apply them after the loop |
| `func` "can have side effects", `gcsafe`, `raises` | `{.cast(noSideEffect).}`, `{.cast(gcsafe).}`, `{.cast(raises: []).}`, an `except` that discards (BN-01) | the effect still happens; only the signature stops saying so | pass the state in and return the change; move data between threads (`details/concurrency.md`); handle or declare the exception |
| a type mismatch | `cast[T]`, `addr`, `ptr`, `unsafeAddr` | no check of lifetime, layout or alignment | a conversion `T(x)`, a `distinct` type with borrowed procs, or a different type (`details/ffi.md` at a C boundary) |
| repetitive code the checks make you write | a template or macro that generates around the check | the same cost in every expansion; errors point into generated code | a proc or a generic, then a template (section 4) |

A `cast` pragma or a `cast[T]` stays only with a comment that says why it is sound, as section 8
asks. "It compiled" is not that reason.

## Read, decide, then write

When a loop must change the collection it reads (a unit that dies, an element that spawns
another), do not reach for `ref` or a copy of the collection. Read in one loop and record the
changes as values; apply them after the loop. The `for` loop over a `seq` asserts that the length
does not change while it runs, so adding inside it fails at run time (unless `-d:danger` removed
the assertion, and then it reads past the old length).

```nim
type
  Unit = object
    hp: int
    alive: bool
  ChangeKind = enum
    chDamage, chKill
  Change = object
    target: int
    case kind: ChangeKind
    of chDamage: amount: int
    of chKill: discard

func plan(units: openArray[Unit]; damage: int): seq[Change] =
  ## Reads only: decides what happens to each unit.
  for i, u in units:
    if u.alive:
      result.add Change(target: i, kind: chDamage, amount: damage)
      if u.hp <= damage:
        result.add Change(target: i, kind: chKill)

proc apply(units: var seq[Unit]; changes: openArray[Change]) =
  ## Writes only, after the reading loop has ended.
  for c in changes:
    case c.kind
    of chDamage: units[c.target].hp -= c.amount
    of chKill: units[c.target].alive = false

var units = @[Unit(hp: 5, alive: true), Unit(hp: 50, alive: true)]
units.apply(plan(units, 10))
doAssert not units[0].alive and units[1].hp == 40
```

A loop that only changes fields of the elements (`for u in units.mitems: u.hp -= d`) keeps the
length and needs no plan; only adding and removing wait for the end of the loop. Collect the
additions in a local `seq` and `add` them after it; remove many elements in one pass with
`keepItIf`, not `delete` in a loop, which shifts the rest on every call.

`openArray[T]` in the reading routine cannot grow or shrink the collection, and a `func` cannot
touch global state. A `func` can still write through a `ref` that a parameter reaches: with
`h: Holder` and a field `box: ref Box`, `h.box.n += 1` compiles in a `func`. Keep `ref` out of
the data a reading routine takes, or turn on `{.experimental: "strictFuncs".}`, which makes that
write an error.

## Cycles

- `{.acyclic.}` is a promise the compiler does not check. A cycle built from an `{.acyclic.}`
  type is never freed, not even by `GC_fullCollect()`, and nothing warns. Put it only on a type
  whose values can never reach themselves: a tree whose nodes own their children and keep no
  pointer back up qualifies; a parent pointer, a back edge or a child shared by two parents does
  not.
- A closure stored in an object that captures that object is a cycle. ARC never frees it and
  warns `CycleCreated`; ORC frees it only when the cycle collector runs, so a resource it owns is
  released later than the end of the scope. Pass the object to the callback as a parameter
  (`proc (b: Button)`) instead of capturing it, or keep the callbacks in one owner and refer to
  the objects by index.
- A parent pointer: an index into the owner's `seq`, or `{.cursor.}` (`details/ownership.md`).

## Measure what the tests do not

For code on a hot path (every frame, every request, every element), check the cost as well as the
result. Two checks a machine can repeat:

- `--expandArc:procName` prints the proc after the compiler inserted copies and destroys, if
  the program calls the proc (build a probe that calls it; a module alone prints nothing). A
  `=copy` inside a loop is an allocation per iteration when the value holds a `seq`, `string` or
  `ref`.
- `-d:nimAllocStats` counts allocations; `getAllocStats()` reads the count. The fields are
  private: `$(getAllocStats() - before)` prints both counts (`(allocCount: 100, deallocCount:
  100)`), and a check compares the difference with `default(AllocStats)`. Without the define,
  `getAllocStats()` always returns zero and every such check passes, so first check that a known
  allocation is counted:

```nim
proc main() =
  let before = getAllocStats()
  var xs = newSeq[int](4)
  xs[0] = 1
  doAssert getAllocStats() - before != default(AllocStats), "build with -d:nimAllocStats"
  let start = getAllocStats()
  var total = 0
  for x in xs: total += x
  doAssert getAllocStats() - start == default(AllocStats), "the read loop allocates"
  echo "read loop: ", getAllocStats() - start   # (allocCount: 0, deallocCount: 0)
  doAssert total == 1

main()
```

When the task names a cost but no workload ("thousands of units", "every frame"), build a
workload of that size in a probe outside the deliverable and report the counts; a cost argued
from reading the code alone is reported as read, not measured.

When the code replaces an original (a port, a rewrite), compare the counts and the time of the
same workload on both, and list each new copy or allocation on the hot path with its reason.
