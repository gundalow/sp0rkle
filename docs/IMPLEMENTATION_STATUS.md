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
- Ordered IRC event dispatch by case-insensitive command, invoking every matching registered callback with the original line and parsed message.
- Session-to-dispatch bridge that receives the next non-PING event, parses it, and immediately invokes the registered command handlers.
- C regression coverage for multiple handlers, case-insensitive matching, null callbacks, no-match dispatch, invalid parsed-message bounds, and socketpair-driven receive/parse/dispatch integration.
- POSIX TCP transport primitives for address resolution/connect, complete-buffer send and bounded CRLF line receive.
- Initial IRC NICK/USER registration command sender.
- Blocking session reader that parses incoming frames and automatically answers PING with PONG.
- Registration completion detection for numeric 001, explicit nickname-in-use reporting for 433, and a channel JOIN sender.
- C socketpair regression tests for NICK/USER/JOIN wire output, welcome/nickname collision handling, PING/PONG and delivery of the next IRC event.
- Minimal logging entry points and a shell smoke-test target.
- Explicit ABI and string ownership conventions in the repository README.
- ASCII-case-insensitive addressed-message prefix stripping and complete PRIVMSG text/addressed-state preparation.
- Command argument normalization that trims and compresses ASCII whitespace.
- Filtered command-processing entry point combining the nick/filter pipeline with addressed gating, factoid bypass, longest-prefix selection and normalized arguments.
- Reference-compatible factoid-addition detection for `:is` and `:=` markers.
- Longest-prefix command help-string lookup and up-to-ten candidate suggestions.
- Nick-ignore filtering with lowercase namespace lookup callback and ordered, short-circuiting filter pipeline.
- Ordered rewrite callback pipeline with alternating caller-owned buffers and failure propagation.

### IRC PRIVMSG Context adapter

- Added `bot_irc_privmsg_views` to validate a parsed user-originated PRIVMSG and expose sender nick, target, and body as pointer/length views into the original line.
- The adapter rejects out-of-bounds slices, requires a nick-bearing prefix (`!` or `@`), and leaves whitespace/addressing policy to `bot_context_prepare_privmsg`.
- Added C regression coverage and `docs/IRC_CONTEXT_ABI.md`; the Makefile builds and runs this test.
- Added `bot_irc_privmsg_context` to compose extraction, Context body/address preparation, and reply-target resolution in one call.
- Regression tests verify addressed channel messages and direct messages produce the expected body, addressed flag, and reply destination. The adapter still does not invoke filters or command handlers.

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


### Context output wrappers

- Added a callback-driven output layer for PRIVMSG, ACTION, and TOPIC.
- Rewrites are applied only when requested, matching Go: Reply/ReplyN/Do rewrite; explicit Privmsg/Action/Topic bypass the rewrite set.
- Added a bounded ReplyN prefix builder and a C ABI test for rewriting, bypass behaviour, callback results, and capacity failures.
- These wrappers are transport-independent; the IRC event loop still needs to resolve Context targets and supply the send callback.

### IRC event dispatch

- Added `irc_event_dispatch` to route a parsed message to all registered handlers for its command, preserving registration order and using ASCII-case-insensitive matching.
- Handler entries are 32 bytes: command pointer, command length, callback pointer, and opaque callback context.
- Callback ABI is `void callback(ctx, original_line, line_len, parsed_message)`. A null callback is skipped; the return value is the number invoked, or `-1` for invalid top-level arguments or command bounds.
- Added `irc_session_dispatch_next` to compose the existing blocking session reader with parsing and ordered dispatch. It handles one non-PING event per call and returns the number of callbacks invoked (zero for an unhandled event), zero for clean EOF, or -1 for transport/parse errors. A socketpair test covers this integrated path. This remains a single-connection blocking primitive: it does not yet construct the full bot Context, dispatch PRIVMSG commands, reconnect, or manage multiple servers.
