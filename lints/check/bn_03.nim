# BN-03: every float now silently becomes an int wherever an int is expected.
converter toInt(x: float): int = int(x)

let n: int = 2.7
echo n
