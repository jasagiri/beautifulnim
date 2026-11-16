type Port {.requiresInit.} = object
  n: int
let p = default(Port)
echo p.n
