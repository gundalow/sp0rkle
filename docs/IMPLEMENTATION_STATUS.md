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

### Karma feature primitives

- Added a byte-span parser for `++` and `--` annotations, including reverse-order result semantics and one-level parenthesised multi-word subjects.
- Added ASCII key normalisation and caller-owned karma record mutation for score, vote count, last upvoter/downvoter and Unix-millisecond timestamps.
- Added schema-specific BSON encode/decode for Karma records, including Go-compatible string, int32/int64 and datetime representations.
- Added SQLite Karma lookup/upsert callbacks and an integration test that applies multiple annotations through the persistent store. Added an IRC event adapter that records PRIVMSG and CTCP ACTION annotations through the SQLite callbacks. The remaining Karma work is Unicode subject parsing, command registration/response compatibility, and exact edge-case conformance.
- Record updates reject signed-score and unsigned-vote overflow without changing the record.
- C tests cover parser examples, record updates and overflow boundaries. Unicode letter/number classification, persistent collection operations, event wiring and command responses remain outstanding.
- Added `karma_apply_annotations`, connecting parsed annotation spans to caller-provided lookup/put callbacks; it creates new records, applies score/vote metadata and persists each change synchronously.
- Added an in-memory callback integration test proving multiple annotations for one subject update the same record. Persistence is intentionally delegated to the future storage layer.

### Database key primitives

- Added byte-exact encoders for string, uint64, boolean, 12-byte ObjectId, and signed Unix-millisecond timestamp key elements using the reference unit separator, plus a length-delimited hierarchical bucket-path encoder.
- uint64 values are encoded as fixed-width eight-byte big-endian values; boolean values use 0xff and 0x00.
- Added key-name validation rejecting the unit separator and capacity checks that leave output untouched on failure.
- Added C regression tests for exact bytes, binary values, invalid names, and insufficient output capacity.
- Added fixed-width 12-byte ObjectId encoding and signed Unix-millisecond timestamp encoding (including pre-epoch values). A durable SQLite BLOB store now supports transactions, upsert/get/delete, atomic per-path sequences, bucket creation/existence, recursive bucket deletion, ordered scans within a bucket, and recursive ordered subtree scans, consistent SQLite snapshot backups, and a database-level integrity check. Karma records now use a schema-specific BSON codec and persistent adapter, and an IRC event callback connects incoming messages/actions to persistent updates. The backend is not BoltDB-file compatible; a generic BSON field lookup/decoder, keyed/indexed collection semantics, collection-level fsck/index repair, scheduled backup rotation/compression, and BoltDB migration remain outstanding. A recursive BSON structural validator now covers the standard element layouts and enforces bounded nesting; a descriptor-driven document encoder writes caller-supplied BSON field values.

### Poller lifecycle

- Added caller-owned poller registry/state and deterministic lifecycle operations.
- Pollers start once when the first IRC connection becomes active, stop once when the last connection disconnects, and can be registered while connected (starting immediately).
- Added ordered synchronous poll dispatch over the caller-supplied Context array; the application scheduler remains responsible for tick intervals and thread execution.
- Added C regression tests for first/last connection transitions, late registration, poll ordering/count, and inactive poll suppression.
- This establishes lifecycle semantics but does not yet implement a timer scheduler, background goroutine equivalent, or full server-set reconnect manager.

### IRC outbound serializer

- Added a bounded serializer/sender for PRIVMSG, CTCP ACTION and TOPIC frames, using the existing complete-send transport primitive.
- Rejects NUL/CR/LF injection in target and text, rejects spaces in targets, and checks scratch capacity before writing.
- Added socketpair regression tests for exact wire frames, ACTION wrapping, injection rejection and insufficient capacity.

### IRC PRIVMSG command pipeline

- Added `bot_irc_privmsg_command_process`, which composes parsed user PRIVMSG extraction, Context preparation, raw-body factoid detection, nick filtering, addressed gating, longest-prefix command matching and argument normalization.
- Added a C integration test covering a channel message through successful dispatch, filter rejection/output clearing, and factoid-addition bypass.
- Added `docs/IRC_COMMAND_ABI.md` and wired the assembly module and regression test into the Makefile.
- Added `bot_irc_privmsg_execute` to invoke the selected handler synchronously using a documented language-neutral callback ABI; regression coverage verifies Context fields, normalized arguments and callback result propagation.
- Domain-specific command implementations and the full runtime lifecycle remain outstanding.

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
2. TLS IRC transport, reconnect/backoff, multi-server management and complete
   event lifecycle; TCP connect/send/receive, registration, parser and outbound
   PRIVMSG/ACTION/TOPIC serialization primitives are implemented.
3. Complete runtime Context/event-handler integration, live command registry
   configuration, built-in help responses, rewrite integration and poller
   timer/background scheduling; lower-level command, rewrite and poller
   primitives are implemented.
4. Durable storage, hierarchical bucket operations, BSON-compatible records,
   keyed/indexed collections, transactions, fsck, sequences and backups; key
   element encoders are implemented.
5. Factoids, complete karma collection/event/command wiring, quotes, seen, URL
   capture/cache/search, statistics, reminders/tells and Markov; karma parser
   and record/update primitives are implemented.
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
GitHub Actions CI assembles the NASM sources, links the executable and C
regression harnesses, and runs `make test` on x86-64 Linux. The latest CI run
for the branch should be checked before treating a newly pushed commit as
validated.


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
