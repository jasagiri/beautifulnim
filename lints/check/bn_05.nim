# BN-05: lowercase type, snake_case proc, and a getter named getX.
type point* = object
  x: int

proc read_point*(s: string): point = point(x: s.len)

proc getX*(p: point): int = p.x
