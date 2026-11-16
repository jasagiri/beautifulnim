# BN-08: a dirty template makes every name in it visible at the call site.
template withTmp(body: untyped) {.dirty.} =
  let tmp = 1
  body
