# BN-09: code assembled as text loses hygiene and the caller's line information.
import std/macros

macro double(name: static string): untyped =
  parseStmt("echo " & name & " * 2")
