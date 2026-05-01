# Test Proposal for sp0rkle IRC Bot

## 1. Executive Summary
This document outlines a comprehensive testing strategy for the sp0rkle IRC bot. The goal is to move from a primarily "test-light" codebase to a robust, professionally verified system. We prioritize areas with high reflection usage (Database), complex parsing (Datetime), and concurrent state management (Bot Core).

## 2. Risk Assessment Methodology
We evaluate each component based on:
- **ROI (Return on Investment)**: The ratio of bug-prevention value to the effort of writing/maintaining the test.
- **Risk of Bug**: Calculated based on code complexity, concurrency requirements, and impact on data integrity.
- **Likelihood**: Probability of a regression or new bug based on the fragility of the implementation (e.g., use of `reflect`, `unsafe`, or global state).

| Risk Level | Description |
| :--- | :--- |
| **High** | Critical path, complex logic, concurrency sensitive, or data-loss potential. |
| **Medium** | Common user features, standard CRUD logic, some state management. |
| **Low** | Simple glue code, boilerplate, or stateless utilities. |

---

## 3. Testing Strategy: Unit vs. Integration

### 3.1 Unit Tests (The Foundation)
**Goal**: Verify logic in isolation.
- **Focus**: `util/`, `db/` (logic parts), `collections/` (logic parts).
- **Strategy**: Table-driven tests covering edge cases, especially for parsers (`datetime`, `calc`) and data transformations.
- **ROI**: High. These are fast and catch logic errors early.

### 3.2 Integration Tests (The Reality Check)
**Goal**: Verify the bot's behavior against a live IRC environment and persistent storage.
- **Focus**: `bot/`, `drivers/`, `collections/` (end-to-end).
- **Strategy**: Testing the full cycle from an IRC message being received to a database update and an IRC response being sent.
- **ROI**: Medium-High. Harder to set up, but essential for catching protocol-level edge cases and concurrency issues.

---

## 4. Integration Test Setup Proposals

We propose 5 different architectures for integration testing:

### Proposal 1: In-Process Mock IRC Server (`MockIRCd`)
Create a lightweight IRC server implementation within the Go test suite using `net.Pipe` or `net.Listen("tcp", "127.0.0.1:0")`.
- **Pros**: Fastest execution; no external dependencies; easy to simulate network failures.
- **Cons**: Only as accurate as our mock; may miss real-world IRCd quirks.

### Proposal 2: GitHub Actions Service Container (Ergo IRCd)
Utilize GHA's `services` field to run an [Ergo IRCd](https://ergo.chat/) instance during CI.
- **Pros**: Tests against a modern, spec-compliant IRCv3 server; highly realistic.
- **Cons**: Slower startup; requires network configuration in CI; harder to debug locally without Docker.

### Proposal 3: External Python/`irc-test` Suite
Use a dedicated IRC testing framework like [irc-test](https://github.com/ergochat/irc-test) to treat the bot as a black box.
- **Pros**: Exceptional coverage of protocol edge cases (malformed lines, weird encoding).
- **Cons**: Requires a different language environment (Python); high setup overhead.

### Proposal 4: Sidecar Container Orchestration (Docker Compose)
Wrap the bot and an InspIRCd/ZNC instance in Docker Compose for local and CI testing.
- **Pros**: Identical environment for developers and CI; can test multi-channel/multi-server scenarios easily.
- **Cons**: Highest resource usage; slower feedback loop.

### Proposal 5: Network Hijacking / Proxy Mock
Run a proxy that captures and replays IRC traffic (like VCR for Go).
- **Pros**: Allows "recording" real production bugs and replaying them exactly in tests.
- **Cons**: Brittle if the IRC protocol implementation changes; hard to generate "new" test cases.

### Comparison Table

| Metric | P1: MockIRCd | P2: Ergo GHA | P3: Python Suite | P4: Docker Sidecar | P5: Record/Replay |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Speed** | Excellent | Good | Fair | Slow | Excellent |
| **Realism** | Fair | Excellent | Excellent | Best | Good |
| **Setup Cost** | Medium | Low | High | Medium | High |
| **Debugging** | Easy | Medium | Hard | Medium | Easy |
| **Negative Testing** | Good | Fair | Best | Fair | Fair |

---

## 5. File-by-File Analysis

### 5.1 Package `bot/` (Core Orchestration)

| File | Purpose | Current Tests | Bug Likelihood | Test Strategy |
| :--- | :--- | :--- | :--- | :--- |
| `bot.go` | Main bot lifecycle (Init, Connect, Shutdown). Manages the global `botData` singleton and register APIs. | No | High | Integration tests for lifecycle state transitions and registration safety (preventing double Init). |
| `commands.go` | Implementation of built-in commands like `ignore` and `unignore`. | No | Low | Unit tests for the ignore/unignore logic and persistence in the `ignore` namespace. |
| `commandset.go` | Registry for bot commands. Implements prefix matching and help dispatching. | Yes | High | Expand unit tests for overlapping prefixes (e.g., `foo` vs `foobar`), case-insensitivity, and help output. |
| `context.go` | Event context wrapper. Provides helpers for `Reply`, `ReplyN`, and access to IRC message fields. | No | Low | Unit tests with mocked IRC connection to verify formatted replies and "addressed" detection logic. |
| `filter.go` | Middleware pipeline for IRC lines. Allows globally ignoring or modifying lines before drivers see them. | Yes | Low | Unit tests for filter ordering and short-circuiting behavior. |
| `handlers.go` | Low-level IRC event handlers (Connected, Notice, Disconnected). Triggers bot state changes. | No | Low | Integration tests to ensure bot correctly responds to IRC server notices and reconnects. |
| `pollerset.go` | Manages background workers (Pollers). Starts/stops them based on connection status. | No | High | Concurrency tests to ensure pollers don't leak or double-start during rapid reconnects. |
| `rewriteset.go` | Global output transformation registry. Allows modifying bot responses before they are sent. | No | High | Unit tests for multiple rewriters. Ensure no infinite loops if rewriters modify output in conflicting ways. |
| `serverset.go` | Manages multiple IRC server connections. Handles multiplexing and event dispatching. | No | Medium | Integration tests involving multiple mock servers to verify cross-server command routing. |

---

### 5.2 Package `db/` (Persistence Layer)

| File | Purpose | Current Tests | Bug Likelihood | Test Strategy |
| :--- | :--- | :--- | :--- | :--- |
| `bolt.go` | BoltDB driver initialization, file locking, and bucket management. | No | High | Integration tests for database locking (ensuring only one instance opens the file) and graceful shutdown. |
| `db.go` | Core database interfaces, constants (prefixes), and BSON serialization helpers. | Yes | Medium | Unit tests for the shared prefix logic and type identification bytes. |
| `indexed.go` | **Critical**: Implements secondary indexes in BoltDB using reflection. Handles index syncing and pointer management. | No | Highest | Exhaustive unit tests for all CRUD operations on complex structs. Verify index cleanup on deletion or update. |
| `keyed.go` | Simple key-value storage implementation for BoltDB buckets. | No | High | Unit tests for direct key access, including binary safety of keys and values. |
| `reflect.go` | Reflection helpers for dealing with pointers and slices in database operations. | No | High | Unit tests for `slicePtr` and type-to-struct mapping. Test with nested and deeply nested structures. |
| `scan.go` | Implementations of database scanners (Match, Index, All). Handles cursor iteration. | No | High | Unit tests for large dataset scanning and regex-based matching efficiency. |

---

### 5.3 Package `collections/` (Data Models)

| File | Purpose | Current Tests | Bug Likelihood | Test Strategy |
| :--- | :--- | :--- | :--- | :--- |
| `conf/config.go` | Configuration namespace for per-nick settings (e.g., timezones). | No | Low | Unit tests for configuration retrieval and type-safe casting. |
| `conf/inmemory.go` | Thread-safe in-memory cache for configuration data. | No | High | Concurrency tests (race detector) for high-frequency reads and writes. |
| `conf/namespace.go` | Logic for isolating configuration settings into namespaces. | No | Low | Unit tests for namespace prefix collisions. |
| `factoids/factoids.go` | Factoid storage and retrieval logic. Defines the `Factoid` schema and indexing. | No | Medium | Unit tests for factoid type detection and complex search queries. |
| `karma/karma.go` | Karma tracking model. Handles increments and decrements in the DB. | No | Low | Unit tests for atomic karma updates. |
| `markov/markov.go` | Markov chain storage. Handles large volumes of word frequency data. | No | Low | Performance benchmarks for markov lookups under high load. |
| `pushes/push.go` | Push notification state and OAuth token management. | No | Low | Unit tests for token expiration and renewal logic. |
| `quotes/quotes.go` | User quote storage and random quote retrieval. | No | Low | Unit tests for quote selection randomness and regex filtering. |
| `reminders/reminders.go` | Reminder and "Tell" persistence. Handles deferred notification scheduling. | Yes | Medium | Expand unit tests for complex reminder durations and recurrence edge cases. |
| `seen/seen.go` | Last-seen tracking for nicknames. Records time, channel, and action. | Yes | Medium | Unit tests for nick normalization and timestamp accuracy. |
| `stats/stats.go` | Channel and global statistics tracking. Aggregates message counts. | No | Low | Unit tests for atomic stat increments across multiple goroutines. |
| `urls/urls.go` | URL history tracking, including shortened and cached versions. | No | Low | Unit tests for URL normalization and duplicate detection. |

---

### 5.4 Package `drivers/` (Feature Implementation)

| File | Purpose | Current Tests | Bug Likelihood | Test Strategy |
| :--- | :--- | :--- | :--- | :--- |
| `calcdriver/calcdriver.go` | Registration for the calculation driver. | No | Low | Integration test for the `!calc` command entry point. |
| `calcdriver/commands.go` | Handler logic for math expressions and bitwise operations. | No | Low | Integration tests for various math strings, including negative inputs and overflows. |
| `decisiondriver/commands.go` | Entry point for `!choose`, `!pick`, and coin flips. | No | Low | Integration tests for multiple choice formats (comma-separated, space-separated). |
| `decisiondriver/decisiondriver.go` | Core logic for random decision making. | No | Low | Unit tests for the random selection algorithm to ensure fairness. |
| `decisiondriver/plugins.go` | Factoid plugin for `$choice` and `$rand` identifiers. | No | Low | Unit tests for plugin replacement in various factoid strings. |
| `factdriver/commands.go` | Factoid management (info, literal, search, delete, edit). | No | Medium | Integration tests for the regex-based `edit` command (`that =~ s/a/b/`). |
| `factdriver/factdriver.go` | Initialization and registration of factoid handlers. | No | Low | Integration test for the basic `:=` and `:is` factoid addition. |
| `factdriver/handlers.go` | Message handlers for learning new factoids and looking them up. | No | Low | Integration tests for lookup priority and "chance of that" settings. |
| `factdriver/plugins.go` | Implementation of factoid identifiers like `$nick` and `$chan`. | No | Low | Unit tests for every identifier to ensure correct replacement context. |
| `karmadriver/commands.go` | Bot-level karma management. | No | Low | Integration test for `!karma <nick>`. |
| `karmadriver/handlers.go` | Detection of `nick++` and `nick--` in general chat. | No | Low | Integration tests for multi-target karma lines (e.g., `a++, b--`). |
| `karmadriver/karmadriver.go` | Karma driver registration and setup. | No | Low | Smoke test for driver initialization. |
| `markovdriver/commands.go` | Markov configuration (learning, ignoring) and `!markov` trigger. | No | Low | Integration tests for markov exclusion lists. |
| `markovdriver/handlers.go` | Passive learning of markov chains from all channel traffic. | No | Low | Integration tests to ensure bot doesn't learn from its own messages. |
| `markovdriver/markovdriver.go` | Markov driver registration. | No | Low | Smoke test for driver initialization. |
| `markovdriver/plugins.go` | Markov-based factoid plugin. | No | Low | Unit test for markov integration within factoids. |
| `netdriver/github.go` | GitHub webhook integration and issue reporting on IRC. | No | Low | Integration tests with mocked GitHub payload delivery. |
| `netdriver/minecraft.go` | Minecraft server status polling and reporting. | No | Low | Integration tests with a mocked Minecraft server response. |
| `netdriver/netdriver.go` | Management of various network-based pollers. | No | Low | Integration tests for poller lifecycle (start/stop). |
| `netdriver/pushbullet.go` | Pushbullet notification integration and OAuth dance. | No | Medium | Integration tests for the OAuth flow and push notification delivery. |
| `netdriver/templates.go` | HTML templates for network-related web pages. | No | Low | Unit tests for template rendering with various data inputs. |
| `netdriver/urbandictionary.go` | Urban Dictionary definition lookups. | No | Low | Integration tests with mocked UD API responses. |
| `quotedriver/commands.go` | Quote management (add, get, random, delete). | No | Low | Integration tests for adding quotes from IRC history. |
| `quotedriver/plugins.go` | Quote-related factoid plugins. | No | Low | Unit tests for quote insertion in factoids. |
| `quotedriver/quotedriver.go` | Quote driver registration and rate limiting. | No | Low | Integration tests for the rate limiting logic (preventing quote spam). |
| `reminddriver/commands.go` | Commands for setting reminders and tells. | No | Medium | Integration tests for complex date strings (e.g., "in 3 weeks on tuesday"). |
| `reminddriver/handlers.go` | Logic for notifying users of pending reminders on join/activity. | No | Low | Integration tests for the "Tell" notification when a user joins a channel. |
| `reminddriver/reminddriver.go` | Reminder driver registration. | No | Low | Smoke test for driver initialization. |
| `seendriver/commands.go` | User command for `!seen <nick>`. | No | Low | Integration test for seen responses and "unknown nick" cases. |
| `seendriver/handlers.go` | Tracking events (join, part, quit, msg) for the seen system. | No | Low | Integration tests for multiple event types (ensuring Part is recorded correctly). |
| `seendriver/seendriver.go` | Seen driver registration and comeback regexes. | No | Low | Integration tests for "easter egg" comeback responses. |
| `statsdriver/commands.go` | Bot and channel stats reporting commands. | No | Low | Integration test for `!stats` output formatting. |
| `statsdriver/handlers.go` | Handlers for capturing stat-worthy events. | No | Low | Smoke test for driver initialization. |
| `statsdriver/statsdriver.go` | Stats driver registration. | No | Low | Smoke test for driver initialization. |
| `urldriver/commands.go` | URL shortener and cache commands. | No | Low | Integration tests for `!shorten <url>`. |
| `urldriver/handlers.go` | Passive URL title sniffing in channels. | No | Low | Integration tests with mocked websites to verify title extraction. |
| `urldriver/http.go` | HTTP client helpers for the URL driver. | No | Low | Unit tests for user-agent and timeout handling. |
| `urldriver/urldriver.go` | URL driver registration and size limits. | No | Low | Integration tests for handling very large pages (ensuring bot doesn't hang). |

---

### 5.5 Package `util/` (Core Libraries)

| File | Purpose | Current Tests | Bug Likelihood | Test Strategy |
| :--- | :--- | :--- | :--- | :--- |
| `bson/bson.go` | Main BSON API. Provides `Marshal` and `Unmarshal` entry points. | Yes | High | Fuzz testing for arbitrary binary input to `Unmarshal`. |
| `bson/decimal.go` | BSON support for decimal types (often used in financial/stats). | Yes | Medium | Unit tests for precision loss and overflow during decimal conversion. |
| `bson/decode.go` | **Critical**: Complex BSON decoding logic. 800+ lines of reflection and pointer manipulation. | No | High | Exhaustive tests for all BSON types. Property-based testing for round-trips. |
| `bson/encode.go` | **Critical**: Complex BSON encoding logic. 500+ lines of reflection. | No | High | Verify encoding of deeply nested maps and custom types. |
| `calc/calc.go` | Shunting-yard expression evaluator for `!calc`. | Yes | Medium | Fuzz testing for malformed math expressions and resource exhaustion. |
| `datetime/lexer.go` | Custom lexer for the date/time parser. Handles time units and relative offsets. | No | Medium | Unit tests for ambiguous time strings (e.g., "now", "tomorrow"). |
| `datetime/tokenmaps.go` | Mapping of tokens to their numeric/semantic values in the parser. | No | High | Verify mapping for all supported locales and shorthand dates. |
| `datetime/y.go` | **Critical**: The generated yacc parser for dates. Extremely complex and fragile. | No | Medium | Regression suite for hundreds of real-world date strings. Grammar coverage testing. |
| `lexer.go` | String tokenizer for bot command parsing. Handles quotes and escapes. | Yes | Low | Unit tests for weird quoting scenarios (e.g., nested quotes, trailing backslashes). |
| `markov/markov.go` | Markov chain generation logic. Handles word selection and ending preferences. | No | Low | Unit tests for chain stability and "loop" prevention. |
| `push/api.go` | Pushbullet API client logic. | No | Low | Unit tests with mocked Pushbullet JSON responses. |
| `utils.go` | Shared helpers for IRC formatting, nick cleaning, and prefix removal. | Yes | Medium | Unit tests for `RemoveColours` and `RemoveFormatting` against various IRC clients' outputs. |

---

## 6. Risky and Fragile Areas

1.  **Reflection in `db/indexed.go`**: The `dupe` and `dupeR` functions are critical for data safety during index cleanup. A bug here causes silent data corruption or panics.
2.  **Concurrency in `bot/serverset.go`**: Managing multiple server connections and dispatching to shared drivers requires perfect mutex discipline.
3.  **Date Parsing in `util/datetime`**: The yacc-based parser is extremely fragile. Small changes to the grammar can cause "tomorrow" to be parsed as "yesterday" or trigger infinite loops.
4.  **BSON Decoding in `util/bson/decode.go`**: Direct byte-to-struct mapping using reflection is a common source of memory leaks or panics if the input BSON is malformed.

---

## 7. Future-Proofing and Stability

### 7.1 Stable Driver API
To allow other developers to add drivers safely, we propose:
- **Contract Tests**: A suite of tests that any `bot.Handler` or `bot.Command` must pass.
- **Isolation**: Ensuring one driver crashing or hanging (e.g., in a regex) doesn't kill the whole bot.

### 7.2 Negative & Malicious Testing
- **IRC Injection**: Test that messages containing `\r\n` are properly handled and don't allow "raw" command injection.
- **Resource Exhaustion**: Test how the bot handles factoids with 10,000 characters or 1,000 recursive plugin replacements.
- **Malformed UTF-8**: Ensure the parser and database don't choke on invalid byte sequences.

---

## 8. Conclusion
The proposed testing suite focuses on the highest-risk areas (Database reflection and Date parsing) while providing a scalable integration testing framework (MockIRCd + Ergo) to ensure the bot remains stable as it grows across more channels and servers.
