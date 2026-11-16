# BN-02: at the call site `open("a.txt", true)` says nothing about what true means.
proc open*(path: string; create: bool): File =
  discard
