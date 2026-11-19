# BN-11: copying a Pool copies the pointer, and both copies free it (check --typed only).
type
  Pool = object
    p: ptr int

proc `=destroy`(x: Pool) =
  if x.p != nil: dealloc(x.p)
