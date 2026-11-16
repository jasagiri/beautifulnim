# BN-01: the error is dropped; the caller never learns the file was missing.
import std/os

proc loadConfig(path: string): string =
  try:
    result = readFile(path)
  except IOError:
    discard

echo loadConfig(getTempDir() / "missing.cfg").len
