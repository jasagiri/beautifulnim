# Skill evaluation on small local models — BeautifulNim

Can a small model that runs on the laptop be the executor for tuning the skills? Measured
2026-11-19/20 on a 24 GB Apple Silicon Mac with LM Studio (OpenAI-compatible API, context 32768).
Models: Qwen3-4B, Qwen2.5-3B-Instruct, Qwen2.5-7B-Instruct.

The tasks, hidden tests and traces are not in this repository. They are kept in a private data
store as `skill-eval-2026-11.tar.gz` (34.7 MB, sha256
`6abb409536cc172071cc7a8401a0d05c394043c43d4ce1a455090302ac36243f`): the Claude runs of the
three tuning loops, the 27 Qwen runs and the tool-use probe below. Built binaries and compiler
caches were left out.

## The harness

A small agent loop over the chat completions API with four tools: `read_file` (24 000 characters
per call, with an offset), `write_file` (inside the work directory only), `run` (a shell in the
work directory) and `finish` (the report). System prompt: act only through tool calls, read the
files the task names, verify by running commands, call `finish` with the report. Temperature 0.6.
It is not Qwen's own agent framework; trying one (Qwen-Agent) is left for later.

## 1. The nine skill scenarios (27 runs)

The same nine scenarios the Claude executors ran (three per skill: nim-best-practices, nim-port,
nim-review), 30 turns each. **0 of 27 met their critical items.** Of the 18 coding runs, 3 wrote a
Nim file and none of those compiled. None of the 9 reviews opened the file under review; they
restated the checklist as findings. Qwen3-4B reported command runs that never happened.

## 2. Tool-use probe (90 runs, n = 5 per cell)

Each run gets a fresh work directory and a random token or random numbers, so an answer cannot be
guessed. 12 turns for T1/T2, 16 for the others.

| Task | Prompt | Passes when |
|---|---|---|
| T1 | Read data.txt and report its first line exactly with `finish` | the report holds the token |
| T2 | Write the sum of the integers in data.txt to sum.txt, run `cat sum.txt`, finish with the sum | sum.txt and the report both hold the right sum |
| T1S | Read nim-best-practices/SKILL.md in full first, then T1 | as T1 |
| T4 | Write hello.nim that prints the token, run `nim c -r --hints:off hello.nim`, finish with the printed line | the file compiles and prints the token, `nim c` was run, the report holds the token |
| T4S | Read SKILL.md in full first, then T4 | as T4 |

Passes out of 5:

| Task | Qwen3-4B | Qwen2.5-3B | Qwen2.5-7B |
|---|---|---|---|
| T1 | 5 | 5 | 5 |
| T2 | 2 | 2 | 0 |
| T1S | 3 | 0 | 5 |
| T4 | 1 | 0 | 4 |
| T4S | 3 | 0 | 2 |

What failed, by kind:

1. **Reporting before seeing results.** Qwen3-4B emitted the read or run calls and `finish` in one
   turn, so the report was written before any output came back: "12345" as the sum (T2, twice),
   "[Content of first line]" (T1S, twice).
2. **Mental arithmetic checked against itself.** Qwen2.5-7B summed the numbers in its head in all
   five T2 runs, got them wrong, wrote that number and then "confirmed" it with `cat sum.txt`.
3. **No Nim.** Imports of modules that do not exist (`import stdin`, `import std`), `stdout.println`,
   character literals in single quotes; the program did not compile.
4. **Success reported on failure.** In 13 of the 30 T4/T4S runs the report named the token while
   the program did not compile or was never run (the token is in the prompt, so echoing it is free).

Reading the skill first clearly hurt only Qwen2.5-3B on T1S (5 → 0): after the long document it lost
its work directory and read data.txt from a path that does not exist, or with a character offset
that cut the token. The other differences (Qwen2.5-7B T4 4 → T4S 2, Qwen3-4B T4 1 → T4S 3) are
within what five runs per cell can tell apart.

## Reading

The models can call tools (T1: 15 of 15), so the tool format of the harness is not what stopped
them. They stop at using a tool's result as the ground truth: waiting for it, letting a command do
the arithmetic, and not reporting success the output does not show. Those are below anything the
skill text controls, so these models cannot rank changes to the skills, and a rerun after editing
the skills is not expected to move the 27-run score.

## Limits

- Five runs per cell; one harness; one quantised build per model as LM Studio downloaded it.
- During the first Qwen3-4B T1/T2 runs another client was using the same server, so those
  durations are not comparable; pass/fail is unaffected.
- Larger local models (Qwen3-14B, Qwen3-Coder-30B-A3B) were not tried; whether they fit in 24 GB with
  a 32k context is unmeasured.
