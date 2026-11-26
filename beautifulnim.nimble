# Package
version       = "0.1.0"
author        = "jasagiri"
description   = "Agent skills for idiomatic Nim, tested compiler settings, and a checker for the rules a parser can decide"
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["beautifulnim/cli"]
namedBin      = {"beautifulnim/cli": "beautifulnim"}.toTable()

# Dependencies
requires "nim >= 2.4.2"

task test, "Run the test suite":
  exec "nim test"
