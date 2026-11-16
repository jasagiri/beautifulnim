type Shape = ref object of RootObj
method area(s: Shape): float = 0.0
echo area(Shape())
