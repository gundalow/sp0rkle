# Assembly port implementation status

Target: x86-64 Linux, NASM, System V AMD64 ABI.

## Implemented in the initial foundation

- Branch-specific assembly build using NASM ELF64 objects and the system C
  linker/runtime.
- Executable entry point with `--version`, `--self-test`, and usage handling.
- Shared ASCII case-insensitive comparison, bounded comparison, and bounded string length.
- Explicit-length byte copy and equality primitives.
- IRC line terminator length primitive (CR, LF, or NUL).
- Explicit-length IRC message parser for tags, prefixes, commands, middle parameters and trailing parameters, with a 15-parameter limit.
- POSIX TCP transport primitives for address resolution/connect, complete-buffer send and bounded CRLF line receive.
- Initial IRC NICK/USER registration command sender.
- Blocking session reader that parses incoming frames and automatically answers PING with PONG.
- Registration completion detection for numeric 001, explicit nickname-in-use reporting for 433, and a channel JOIN sender.
- C socketpair regression tests for NICK/USER/JOIN wire output, welcome/nickname collision handling, PING/PONG and delivery of the next IRC event.
- Minimal logging entry points and a shell smoke-test target.
- Explicit ABI and string ownership conventions in the repository README.
- ASCII-case-insensitive addressed-message prefix stripping for bot context creation.
- Command argument normalization that trims and compresses ASCII whitespace.
- Command-dispatch orchestration for addressed gating, factoid bypass, longest-prefix handler selection and normalized arguments.
- Reference-compatible factoid-addition detection for `:is` and `:=` markers.
- Longest-prefix command help-string lookup and up-to-ten candidate suggestions.
- Nick-ignore filtering with lowercase namespace lookup callback and ordered, short-circuiting filter pipeline.

## Not implemented yet

The items below remain required by SPEC.md; this milestone is not a complete
bot implementation.

1. Configuration parsing, startup/shutdown, signals, time zones and logging
   levels.
2. TCP/TLS IRC transport, registration, message parser/serializer, reconnect,
   multi-server management and event lifecycle.
3. Full context object and event-handler integration, command registry wiring,
   help, rewrite pipeline and poller lifecycle.
4. Durable storage, hierarchical key encoding, BSON-compatible records,
   keyed/indexed collections, transactions, fsck, sequences and backups.
5. Factoids, karma, quotes, seen, URL capture/cache/search, statistics,
   reminders/tells and Markov.
6. Calculator, datetime, netmask, character/base/length and random decision
   commands.
7. HTTP short-link/cache server and optional third-party integrations.
8. Reference transcript fixtures and end-to-end tests against a local IRCd.

## Porting sequence

Build the platform/runtime and test primitives first; then implement the IRC
adapter and deterministic bot core; then storage; then domain repositories
and drivers; finally HTTP and optional integrations. Keep every feature behind
small ABI-stable module interfaces. Do not invent unspecified behaviour:
resolve SPEC.md's compatibility backlog with fixtures from the Go reference.

## Validation status

The GitHub source branch has been populated with NASM source and build scripts.
Compilation and tests must be run on an x86-64 Linux host with NASM, GCC, and
Make installed; this remote repository operation cannot itself execute those
commands.
