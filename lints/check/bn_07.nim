# BN-07: two shapes known up front; an object variant with case says so in the type.
type
  Shape = ref object of RootObj
  Circle = ref object of Shape
    r: float

method area(s: Shape): float {.base.} = 0.0
method area(c: Circle): float = 3.14159 * c.r * c.r
