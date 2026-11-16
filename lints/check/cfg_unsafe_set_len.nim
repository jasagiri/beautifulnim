type Port {.requiresInit.} = object
  n: int
var ports: seq[Port]
ports.setLen(3)
echo ports.len
