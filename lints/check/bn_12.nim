# BN-12: the string `s & "\0"` is freed when cname returns; the cstring points into it (check --typed only).
proc cname*(s: string): cstring =
  cstring(s & "\0")
