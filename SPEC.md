# sp0rkle — Clean-room implementation specification

**Status:** implementation-oriented specification derived from the repository's current Go source.  
**Reference implementation:** https://github.com/gundalow/sp0rkle  
**Reference revision:** `master` at the time this document was prepared.  
**Purpose:** describe externally observable behaviour, domain rules, persistence semantics, integration points and operational requirements so that an independent implementation can be written in another language without copying Go implementation details.

This document distinguishes **specified behaviour** (directly visible in the inspected source) from **compatibility questions** (details that require further source inspection, fixtures or a running reference bot). Where behaviour is not established, it is called out rather than guessed. The clean-room implementation should preserve the former and use the latter as an explicit test/research backlog.

## 1. Product overview

sp0rkle is a persistent, multi-purpose IRC bot. It connects to one or more configured IRC servers, joins configured channels, reacts to IRC events, recognises addressed commands, and exposes a collection of conversational features. It stores structured data in an embedded Bolt-compatible key/value database (the current implementation uses bbolt), supports periodic database backups and startup integrity checking, and starts an HTTP server for URL short links/cache files and optional integrations.

The current feature families include:

- IRC connection lifecycle, command dispatch, help, ignore/unignore and message rewriting.
- Factoids: learn, retrieve, edit, delete, search, permissions/chance and metadata.
- Karma scoring.
- Seen tracking for messages and channel/user lifecycle events.
- Quotes.
- URL capture, search, short links and local content caching.
- Per-nick/channel activity statistics and leaderboards.
- Reminders and deferred “tell” messages, including optional push notifications.
- Markov-chain text generation with per-user opt-in/opt-out and tagged corpora.
- Calculator, date/time, network mask, character/base/length utilities.
- Random choice/number and decision helpers.
- Optional integrations: Urban Dictionary, Minecraft server status/topic polling, GitHub issue integration, Pushbullet and flight tracking; optional LLM-backed insult generation.

The bot is intended to run as a long-lived process. IRC disconnect/reconnect is part of normal operation, not a fatal application exit.

## 2. Terminology and core entities

- **Server connection:** one IRC network connection managed by the bot's server manager.
- **Nick:** IRC nickname. Nick comparisons and persistent lookup keys are case-insensitive (normalised with lowercase); the original spelling is retained for display.
- **Channel:** IRC channel name. A channel is retained as received; lookup keys may be lowercased by individual features.
- **Line/message:** parsed IRC protocol event. At minimum it carries command/event name, source nick, arguments, text, and optional other nick/action information.
- **Context:** per-event view passed to handlers. It contains a copy of the IRC line, the bot's current nick, network identity, whether the bot was addressed, and reply/action methods.
- **Driver:** feature module that registers event handlers, commands, rewrite functions and pollers with the bot.
- **Collection:** typed domain-facing wrapper around persistent storage.
- **Keyed collection:** stores one value at a hierarchical key.
- **Indexed collection:** stores values by stable object identifier and maintains one or more secondary indexes.
- **Factoid:** one value associated with a lookup key. A key can have multiple values.
- **Tell:** a reminder-like message delivered when the target nick is next observed; unlike a scheduled reminder it has no due timestamp.
- **Poller:** background task started on IRC connection and stopped on disconnect.

## 3. Process lifecycle and configuration

### 3.1 Startup sequence

The process must perform these steps in order:

1. Parse command-line flags.
2. Initialise application logging and IRC-library logging.
3. Load the configured default time zone. Failure to load it is fatal.
4. Seed the pseudo-random generator.
5. Open the embedded database. Failure is fatal.
6. Initialise all persistent collections and their buckets.
7. Construct the shared configuration registry and bot instance.
8. Construct/register feature drivers and their event handlers, commands, rewrite functions and pollers.
9. Start the HTTP server asynchronously.
10. Install interrupt handling.
11. Connect to IRC and block until the bot signals shutdown/rebuild completion.
12. Close the database and exit cleanly.

A second interrupt is treated as an emergency termination: close the database and terminate rather than waiting for graceful shutdown.

### 3.2 Command-line flags observed

| Flag | Default | Meaning |
|---|---|---|
| `http` | `:6666` | HTTP listen address |
| `http_host` | `https://s.pl0rt.org` | Public host used when constructing HTTP paths |
| `boltdb` | `sp0rkle.boltdb` | Database file path |
| `backup_dir` | `backup` | Backup directory |
| `backup_every` | `24h` | Backup interval |
| `timezone` | `Europe/London` | Default time zone for date/time operations |
| `backup_on_startup` | `true` | Run an initial backup |
| `fsck_on_startup` | `true` | Run collection integrity checks after registration |
| `url_cache_dir` | `$HOME/.sp0rkle` | Directory for cached URL bodies |

Logging flags are supplied by the logging libraries and are not exhaustively specified here.

### 3.3 Runtime configuration registry

A persistent namespaced key/value registry is used for feature configuration rather than a single static config file. Observed namespaces include:

- `ignore`: lowercased nick → ignore marker.
- `timezone` (constant name is exposed by the datetime package): lowercased nick → IANA time-zone name.
- `mc`: Minecraft server/poller configuration.
- `markov`: user Markov opt-in state.

Namespace operations include string get/set and delete. Secret values may be represented as:
- literal text;
- `$NAME`, expanded from the process environment;
- `<path>`, read from a file, with one trailing newline removed. A failed file read yields an empty value.

The exact full schema for the Minecraft namespace and any additional runtime keys should be confirmed against the relevant driver methods before implementation.

## 4. IRC connection and event processing

### 4.1 Connection behaviour

The bot owns a server set responsible for establishing and managing configured IRC connections. It registers handlers against IRC event names and exposes a connection lifecycle signal. The application must automatically reconnect/rebuild connections when the server manager requests it. The precise retry/backoff policy and server configuration source are not established in the files inspected for this specification and must be confirmed.

On connection:
- the bot marks itself connected;
- the nick-ignore filter is installed;
- registered pollers are started.

On disconnection:
- registered pollers are stopped;
- the connection manager handles reconnect/rebuild lifecycle.

Shutdown disconnects all servers and resets the filter pipeline. Repeated connect/shutdown calls should be guarded and logged rather than silently corrupting state.

### 4.2 Event handler pipeline

A handler registration associates one callback with one or more IRC event names. There are synchronous and background variants:

- **Synchronous handler:** invoked inline by event dispatch.
- **Background handler:** invoked through the IRC library's background-handler mechanism.

Before invoking a handler, apply the filter pipeline. If any filter rejects an event, no handler should process it. The built-in nick-ignore filter permits events without a source nick and rejects events whose source nick is in the ignore namespace.

Handlers receive a fresh context with a copy of the incoming line. Do not let one handler's mutations leak into other handlers.

### 4.3 Context semantics

The context exposes:
- source nick;
- IRC command/event;
- event arguments and text;
- channel/target information;
- the bot's own nick;
- network/server identity;
- an `Addressed` boolean;
- methods to send a normal message, action, topic update, or channel/user private message.

For PRIVMSG:
1. Trim surrounding whitespace from message text.
2. Remove a leading bot nickname plus its supported addressing punctuation/spacing using the IRC utility's prefixed-nick parser.
3. Mark the message addressed if that parser matched.
4. Also mark a private message addressed when the PRIVMSG target is the bot's own nick.

For other event types, do not apply PRIVMSG addressing parsing.

Reply target is the context's target (normally the channel for a channel message and the sender for a private message). `ReplyN` prefixes the source nick and `: `; `Reply` does not. `Do` emits an IRC ACTION. Reply text is passed through registered rewrite functions before being sent. Explicit `Privmsg` and `Action` methods send to the supplied target and do not implicitly add a nick prefix.

### 4.4 Command matching and dispatch

Commands are registered with:
- a literal text prefix;
- a handler;
- a human-readable help string.

Rules:
- Prefix matching is case-insensitive.
- A message must be addressed to the bot before a registered command runs.
- The longest matching prefix wins. This is important because prefixes overlap (for example `quote` and `quote #`).
- After matching, remove the matched prefix, trim and compress remaining whitespace, and pass that as command text.
- Duplicate prefixes are rejected/logged; empty prefixes and nil handlers are rejected/logged.
- The command registry is safe for concurrent reads and writes.
- Factoid-addition syntax is checked before command dispatch; a line recognised as a factoid addition must not be consumed as a command even if it begins with a command prefix.

The built-in `help` command behaves as follows:
- no argument: return the project wiki URL and a contribution invitation;
- argument matching a command prefix: return that command's help string;
- otherwise: search registered prefixes for ones containing any input word, return up to ten candidates;
- if none: return an unrecognised-command response.

The command registry's own help text is a deliberately unhelpful quip. Preserve exact wording only if strict transcript compatibility is required.

### 4.5 Rewrite pipeline

Drivers may register rewrite functions. A rewrite receives the output string and message context and may replace tokens/expressions with dynamic output. Rewriters are applied when the bot sends context-based replies. At minimum, the decision driver registers random-number and decision rewrites; the factoid driver registers identifier replacement; the quote driver registers quote-related replacement; the Markov driver may register an insult plugin when its optional backend is enabled.

Ordering is registration order unless the reference implementation demonstrates otherwise. The rewrite set's exact iteration and error semantics need confirmation.

## 5. Persistence layer

### 5.1 Database requirements

The reference uses bbolt, a transactional embedded key/value store. A compatible implementation may use another database, but must preserve:
- durable local storage;
- atomic writes for one value and batches;
- hierarchical byte keys;
- deterministic lexicographic key ordering where used for indexes;
- monotonically increasing per-bucket sequences;
- concurrent read transactions and serialised write transactions;
- backup and restore capability;
- integrity checking/rebuilding of secondary indexes.

The clean-room implementation should define a storage abstraction independent of its chosen database engine.

### 5.2 Common collection interface

Every collection supports the conceptual operations:

- `Get(key)`: retrieve one value.
- `All(key)`: retrieve all values below a key prefix; an empty key means all values.
- `Match(predicate)`: scan values and return those satisfying a predicate.
- `Put(value)`: insert or replace a value.
- `BatchPut(values)`: insert/replace a group atomically.
- `Del(value)`: delete a value and associated indexes.
- `Next(key, optionalSet)`: increment or explicitly set a sequence associated with a key.
- `Debug(enabled)`: enable diagnostic logging.
- `Fsck()`: validate values/indexes and repair inconsistencies.

Missing keys return an empty/zero result without treating absence as a fatal storage error. Storage/decoding failures are returned to the caller.

### 5.3 Key encoding

A key is a sequence of named typed elements. Each element encodes to bytes as follows:

- String: UTF-8 bytes of name, one unit-separator byte (`0x1f`), then UTF-8 value.
- Unsigned integer: name, unit separator, then exactly eight bytes, big-endian.
- Boolean: name, unit separator, then one byte: false `0x00`, true `0xff`.
- Object ID: name `_id`, unit separator, then the ObjectId bytes.
- Timestamp: same encoding as an unsigned integer containing Unix milliseconds. Truncate timestamps to millisecond precision before encoding.

The record separator constant is ASCII `0x1e`; the unit separator is ASCII `0x1f`. Key element names must not contain the unit separator. Values are not prohibited from containing it. A key's elements except the last are nested bucket names; the last is the actual key in the final bucket. Empty keys are valid for full scans and sequence operations, but not for a single-value Get/Put/Delete.

### 5.4 Keyed collections

A keyed collection stores BSON-encoded values directly at the key returned by the value's key method. Put creates missing nested buckets and replaces any existing value at the same key. Delete removes either a value or, when the final key identifies a nested bucket, the bucket recursively. BatchPut must be one transaction. A value validator can request deletion of invalid/duplicate values during Fsck.

### 5.5 Indexed collections

An indexed collection stores each value once in a values bucket under a reserved ObjectId pointer. It maintains secondary index buckets for every key returned by the value's index method. Each secondary index leaf maps to the ObjectId pointer.

- Get resolves the supplied index key to a pointer, then loads the canonical value. A direct ObjectId key bypasses the secondary-index lookup.
- All resolves an index prefix and loads all pointed-to values. Empty key scans all canonical values.
- Match scans canonical values and evaluates the predicate.
- Put validates keys and ObjectId, removes old index entries if replacing an existing ObjectId, writes the canonical BSON value, and writes all new index entries atomically.
- Delete removes the canonical value and all indexes derived from that value.
- Fsck performs a value validation pass (if the value type supplies a validator), then reconciles indexes against canonical values in both directions.

An ObjectId is a stable unique identifier. The reference's ObjectId representation is BSON-compatible; another language may use a 12-byte binary identifier but must preserve round-trip compatibility if migrating existing database files.

### 5.6 BSON and migration

The current database stores BSON-encoded records, including time values and ObjectIds. A new implementation that needs to read existing database files must implement compatible BSON encoding/decoding and preserve field names/types. If it intentionally starts with a new database, document that migration is not supported and provide an import/export format.

Do not silently change case-normalisation, timestamp precision, index key encoding or ObjectId representation: those choices affect lookup and deduplication.

### 5.7 Collection registration and startup fsck

At startup register these named collections:

| Collection | Storage type | Purpose |
|---|---|---|
| `karma` | keyed | Karma scores |
| `quotes` | indexed | Quote records |
| `seen` | indexed | Last-seen events |
| `urls` | indexed | Mentioned URLs and metadata |
| `stats` | indexed | Nick/channel counters |
| `pushes` | indexed | Push notification credentials/aliases |
| `factoids` | indexed | Factoid values |
| `reminders` | indexed | Reminders and tells |
| `markov` | custom bbolt bucket | Markov transition counts |
| `conf` | keyed | Namespaced configuration and ignore state |

If startup fsck is enabled, run integrity checking on all registered collections after registration and before normal operation. Fsck must be safe to run repeatedly.

### 5.8 Backups

The database layer is configured with a backup directory and interval; the application can request a backup on startup. Backups must represent a consistent database snapshot. The precise naming/rotation policy should be confirmed from the database package before claiming compatibility.

## 6. Domain model and feature behaviour

### 6.1 Karma

**Record fields:** display subject, lowercase lookup key, integer score, vote count, last upvoter/time and last downvoter/time.

- A new subject's lookup key is lowercase(subject).
- Upvote increments score and total votes and records voter/time.
- Downvote decrements score and increments total votes and records voter/time.
- Query is case-insensitive by lowercased subject.
- Display includes subject, score, vote count and last up/down voter timestamps when present.

**IRC behaviour:** monitor PRIVMSG and ACTION for karma expressions and provide a `karma <thing>` query command. Expression recognition is a lexer, not a naive substring search: it recognises `++` and `--` suffixes, supports parenthesised multiword subjects, and otherwise consumes Unicode letters/numbers as the subject. The expression must be separated from preceding text by whitespace or start-of-message. Do not count empty subjects. Exact edge cases for repeated markers, nested parentheses, self-voting and duplicate votes need reference tests.

### 6.2 Factoids

**Record fields:**
- `Key`, `Value`;
- `Chance` (float, default 1.0);
- `Type`: fact (0), action (1), URL (2);
- `Created`, `Modified`, `Accessed` stats, each containing timestamp, nick, channel and count;
- `Perms`: read-only flag and owner nick;
- BSON ObjectId.

A key can have multiple factoids. The secondary index is key plus unique ObjectId. New factoid creation sets all three stats to current time/nick/channel; created count starts at 1, modified/accessed counts at 0; owner is creator; read-only is false.

Value parsing:
- Prefix `<me>`: action type; remove the prefix.
- Prefix `<reply>`: normal fact type; remove the prefix.
- Otherwise normal fact type.
- If the resulting value looks URL-like, type becomes URL.

Access increments access count and updates timestamp/nick/channel. Modify increments modification count and updates same metadata. Factoid lookup uses key, and when multiple values exist the collection has pseudo-random selection without repeating an ObjectId for that key until all candidates have been selected. When exhausted, clear the seen set and begin a new cycle. A sole result is returned directly.

Key normalisation used by the factoid driver:
1. lowercase;
2. trim leading/trailing `!`, `?`, `.`, comma and spaces;
3. remove IRC formatting and colour codes;
4. optionally remove common linguistic prefixes (the call site decides whether).

The driver registers:
- insertion handler on PRIVMSG;
- lookup handler on PRIVMSG and ACTION;
- rewrite handler for factoid identifier replacement;
- `chance of that is`: set trigger chance on the last displayed value;
- `that =~`: apply a sed-like regex substitution to the last displayed value;
- `delete that` and `forget that`: delete last displayed value;
- `fact info <key>`: aggregate created/modified/accessed counters;
- `literal <key>`: display stored values literally;
- `replace that with`: replace last displayed value;
- `fact search <regexp>`: search keys by case-insensitive regular expression.

The last displayed factoid is tracked per channel, not globally. `GetLast` returns the latest-created, latest-modified and latest-accessed records for a key. Search returns unique keys. Invalid regular expressions should fail safely rather than crash. Permission enforcement, chance threshold interpretation, insertion grammar, exact lookup trigger grammar, and identifier syntax must be confirmed from the remaining factdriver methods before implementation; do not infer them from command names alone.

### 6.3 Quotes

**Record fields:** quote text, integer QID, submitting nick, channel, access count, timestamp, ObjectId. Indexed by QID; ObjectId is canonical identity.

Commands:
- `qadd`, `quote add`, `add quote`: add quote.
- `qdel`, `quote del`, `del quote`: delete by QID.
- `quote #<qID>`: fetch exact quote.
- `quote <regex>`: retrieve quote matching regex.

A new quote gets current time, submitter/channel, access count zero, and a new ObjectId. QIDs come from a collection sequence. Regex selection is case-insensitive and pseudo-random without replacement per regex until candidates are exhausted. If there is one result, return it directly and reset the seen set. Quote lookup is rate-limited per nick: token/badness accumulation is 15 seconds per request, capped by a 60-second threshold (equivalent to a burst allowance of four at a 15-second cadence). Exact rate-limit response and access-count mutation are to be confirmed in the remainder of the driver.

A quote rewrite plugin is registered. Its exact token grammar must be confirmed.

### 6.4 Seen tracking

**Record fields:** nick, channel, other nick, timestamp, lowercase key, action/event name, text and ObjectId.

Recorded event classes:
- PRIVMSG and ACTION;
- JOIN and PART;
- NICK and QUIT;
- KICK (both the kicker and kicked user perspectives);
- a special smoke status event.

The action-specific rendering rules are:
- PRIVMSG: “in channel, saying 'text'”.
- ACTION: “in channel, saying 'nick text'”.
- JOIN: “joining channel”.
- PART: “parting channel with the message 'text'”.
- KICKING: “kicking otherNick from channel with the message 'text'”.
- KICKED: “being kicked from channel by otherNick with the message 'text'”.
- QUIT: “quitting with the message 'text'”.
- NICK: “changing their nick to 'newNick'”.
- SMOKE: fixed “going for a smoke.” text.
- Unknown action: generic last-seen timestamp/elapsed-time response.

For each nick/action pair, only the newest event should survive. The collection's value validator removes older duplicates. Indexes support lookup by nick+action and by nick with timestamp ordering. `LastSeen(nick)` returns the newest event across actions; `LastSeenDoing(nick, action)` returns the newest for that action. Regex search is case-insensitive and returns unique nicks ordered by timestamp.

Command: `seen <nick> [action]`.

A smoke detector watches PRIVMSG/ACTION for a set of smoke-related phrases and records a special smoke event. It also has a fixed set of witty responses to a small set of “who is …” style questions; exact trigger logic and responses should be transcribed from the full driver if strict compatibility is required.

### 6.5 URLs

**Record fields:** source nick, channel, timestamp, original URL, cache identifier/time, content hash, MIME type, short identifier and ObjectId.

Indexes:
- original URL;
- cache identifier, when set;
- shortened identifier, when set;
- direct ObjectId.

URL records are created when URLs are detected in channel PRIVMSG. Collection operations include get by ObjectId, original URL, cached identifier and shortened identifier. Random/search selection supports case-insensitive regex matching and avoids repeating selected ObjectIds for a regex until the candidate set is exhausted.

Commands:
- `urlfind <regex>`, `url find <regex>`, `urlsearch <regex>`, `url search <regex>`: search prior URLs.
- `randurl`, `random url`: random prior URL.
- `shorten that`, `shorten <url>`: create short identifier.
- `cache that`, `cache <url>`, `save that`, `save <url>`: download and cache content.

HTTP endpoints:
- `/s/<id>`: resolve a shortened URL.
- `/c/<id>`: serve a cached file from the cache directory.

Short/cache IDs are derived from a CRC32-IEEE checksum of the URL, converted to four bytes and URL-safe base64 encoded, taking the first six characters. On collision, mutate one checksum byte and retry, at most ten attempts. The reference checks both existing cached and shortened IDs for collisions.

Cache operation:
1. Reject URLs containing any configured forbidden substring; the observed list contains `4chan`.
2. Issue HTTP HEAD; require status 200.
3. If Content-Length is present, parse it and reject values above 4 MiB.
4. Issue GET; reject response Content-Length above 4 MiB.
5. Write response body to a file named by cache ID with owner-only read/write permissions.
6. Store cache timestamp and Content-Type in the URL record.

The reference cache maximum is 4 MiB. A robust reimplementation should additionally enforce a streaming byte limit even when the server omits Content-Length, set network timeouts, validate schemes, and prevent SSRF/private-network access; these are security improvements and may change legacy compatibility. Redirect handling and error responses need explicit tests.

### 6.6 Channel statistics

**Record fields:** nick, lowercase nick key, channel, line count, word count, character count, 7×24 activity histogram and ObjectId.

For each PRIVMSG/ACTION:
- increment line count;
- add the number of whitespace-separated fields to word count;
- add string length to character count (reference Go string length is UTF-8 byte count, not Unicode grapheme count);
- increment activity bucket for current weekday and hour.

The reference uses the process local time for activity buckets. The most-active slot is the first maximum encountered when scanning weekday then hour. Average words/line and chars/line are floating point values formatted to two decimals.

Commands:
- `lines [nick]`, `stats [nick]`: display statistics for the sender or named nick in the current channel.
- `topten`, `top10`: display up to ten nicks sorted by descending line count.

Indexes support channel+nick and channel+line count. Equal line-count ordering is not guaranteed.

### 6.7 Reminders and tells

**Record fields:** source nick, target nick, channel, lowercase source/target keys, message text, creation time, due time, tell flag and ObjectId.

A scheduled reminder has a due timestamp. A tell has no due timestamp and is delivered when the target is next observed. Both are indexed by tell flag and source/target plus timestamp.

Commands:
- `tell <nick> <msg>` and `ask <nick> <msg>`: store a tell.
- `remind <nick> <msg> in|at|on <time>`: schedule a reminder.
- `remind list`: list reminders set by or for the caller.
- `remind del <N>`: delete an item by the index from the caller's most recent list.
- `snooze [duration]`: reinstate the previously triggered reminder.
- `my timezone is <zone>`: set the caller's IANA time zone.
- `forget my timezone`: clear the caller's override.

Reminder reply text distinguishes:
- tell: “source asked me to tell you message”;
- self-reminder: “source, you asked me to remind you message”;
- reminder for another nick: “target, source asked me to remind you message”.

Acknowledgement text similarly distinguishes tells, self-reminders and reminders for another user. Listing text depends on whether the caller is sender, target or both. Sort scheduled reminders by due time.

On IRC connection, load future scheduled reminders and prune expired ones. For each future reminder, schedule a cancellable task against the bot's root context and due time. On due time:
- send reminder text to the original channel;
- also send it to the target nick;
- retain the reminder as the most recently finished reminder for snooze;
- if push notifications are enabled and target has a push-capable device, send a push notification;
- delete the persisted reminder.

On disconnect, cancel in-memory reminder goroutines; persisted future reminders remain for reload after reconnect. Tell delivery is triggered by subsequent PRIVMSG/ACTION/JOIN/NICK observations of the target; exact ordering and duplicate prevention should be tested.

Per-user time zones are lowercased by nick. Supplying an empty zone deletes the override. Invalid zones must be rejected with a useful message. Date parsing and natural-language time grammar are delegated to the datetime utility and should be ported with a compatibility test corpus.

### 6.8 Markov text generation

Markov data is stored in a dedicated bbolt bucket because of volume. Structure:
- top-level bucket `markov`;
- child bucket per tag;
- child bucket per source token;
- key per destination token;
- value is an unsigned-varint transition-use count.

Adding a sentence starts from a sentence-start sentinel, splits text on whitespace, increments each source→destination transition, then increments the final token→sentence-end transition. Adding an action starts from a separate action-start sentinel. If either source or destination looks URL-like, skip that transition. Use atomic database updates for each transition increment.

A Markov source reads all destination links and counts for a given tag/source. Generation should choose next tokens weighted by transition counts, follow transitions until an end sentinel or safety limit, and avoid unbounded loops. The exact sampling algorithm and stop/length limits live in the Markov utility and need a source-level compatibility pass.

Driver behaviour:
- record PRIVMSG and ACTION when the speaker has opted in;
- `markov me`: enable recording for caller;
- `don't markov me` and `don't markov me, bro`: disable and delete caller's recorded data;
- `markov <nick>`: generate a sentence for that nick;
- `learn <tag> <sentence>`: add manually supplied tagged sentence;
- when optional Llama backend is enabled, register an insult rewrite and `insult <nick>` command.

### 6.9 Calculator and utility commands

The calculator driver registers:
- `calc <expr>`: evaluate a mathematical expression;
- `date <time/date> [in <zone>]`: resolve a date/time in a zone;
- `netmask <ip/cidr>|<ip> <mask>`: calculate IPv4/IPv6 masks;
- `chr <int>`: show character representations;
- `ord <char>`: show numeric and UTF-8 representations;
- `base <from>to<to> <num>`: convert number bases;
- `length <string>`: report string length.

The date command uses the same per-user time-zone namespace as reminders. Expression grammar, supported numeric bases, error wording, and IP edge cases should be derived from the driver methods and utility tests.

### 6.10 Decisions and random values

The decision driver registers:
- `rand <range>`: random number in `[lo-]hi`, optionally followed by a formatting expression. Without a lower bound, lower bound is zero. Default output format is zero decimal places. Invalid numeric bounds are treated as zero by the observed helper.
- `decide <options>` and `choose <options>`: choose one option at random.

Option splitting heuristics:
1. If the input contains quoted strings in a recognised mixed form (quoted phrases alongside bare words), parse bare words separated by whitespace and quoted phrases that may contain spaces and pipe characters.
2. Otherwise, if a pipe exists, split on pipe.
3. Otherwise split on spaces.
Unbalanced quotes in mixed mode return an error. The rewrite plugins expose random-number and decision expansion in ordinary replies; exact token syntax is to be confirmed from the remaining driver source.

### 6.11 Network/internet integrations

The network driver always registers:
- `ud <term>`: Urban Dictionary lookup.
- Minecraft poller configuration command `mc set <key> <value>`.
- If a configured Minecraft server is available and can be polled, start a poller and handle IRC numeric 332 (topic) in a background handler.

When a GitHub token is configured:
- watch channel messages for GitHub-related activity;
- register `file bug: <title>. <body>`, `file bug <title>. <body>`, and `report bug <title>. <body>` to create issues;
- register `update bug #<number> <comment>` to add a comment.

When Pushbullet is enabled:
- `push enable`, `push disable`, `push auth <pin>`, `push add alias`, `push del alias`;
- HTTP routes `/oauth/auth`, `/oauth/device`, `/oauth/success`, `/oauth/failure`.

When flight tracking is enabled:
- `stalk <flight>` and `flight tracking start <flight>`;
- `unstalk <flight>` and `flight tracking stop <flight>`;
- `flight status <flight>`;
- `flight alias <flight> <alias>`;
- start the flight poller.

These integrations are optional and must be disabled cleanly when credentials/configuration are absent. Network calls should have bounded timeouts, errors should not crash the IRC event loop, and pollers must stop on disconnect/shutdown.

## 7. HTTP service

The HTTP listener defaults to port 6666. It is started independently of IRC. Registered routes include:
- `/s/`: short-link resolver, with the path prefix stripped before lookup.
- `/c/`: static file server rooted at the URL cache directory, with the path prefix stripped.
- Pushbullet OAuth routes when push support is enabled.

The implementation should:
- use the configured public HTTP host when constructing URLs sent to IRC;
- return a redirect for a known short ID;
- return a clear not-found response for unknown IDs;
- prevent path traversal from cache identifiers;
- use restrictive file permissions for cached content;
- expose operational errors in logs, not to IRC users as stack traces.

Exact redirect status code and OAuth request/response payloads require inspection of the corresponding remaining methods.

## 8. Concurrency and failure handling

- Command registry supports concurrent registration and matching with read/write locking.
- Database writes are transactional.
- Event handlers may run synchronously or in the background; feature code must not assume global serial execution.
- Pollers have explicit start/stop lifecycle hooks.
- Reminder tasks are cancellable and rooted in the bot context.
- Shared maps (rate limits, per-channel last factoid, URL/quote pseudo-random history, flight state, reminder indexes) must be protected against concurrent access in a new implementation, even where the reference code's synchronisation is incomplete.
- A malformed user regex, invalid date, unavailable remote API, missing record or transient network failure should produce a controlled error/no-result, not terminate the process.
- Logging levels include debug/info/warn/error/fatal.

## 9. Security and privacy requirements

A clean-room implementation should preserve the feature's trust boundaries and improve unsafe edges:

- Never log OAuth tokens, push tokens, GitHub tokens, or secret file contents.
- Keep secret-bearing configuration out of IRC output.
- Restrict cache directory and files; validate short/cache IDs before filesystem access.
- Apply a streaming cache-size limit, request timeouts, redirect limits and SSRF protections.
- Validate URL schemes (HTTP/HTTPS only unless explicitly supported).
- Escape or neutralise control characters in remote data before sending to IRC.
- Bound regex input length and execution cost.
- Bound Markov generation length and poller work.
- Require appropriate permissions for destructive factoid/reminder/Markov operations.
- Treat nick identity as IRC-network scoped if the bot ever supports multiple networks; do not accidentally merge users across networks.
- Preserve explicit Markov opt-out as deletion of the user's stored corpus, not merely a future-recording flag.

## 10. Clean-room implementation architecture

Recommended language-neutral modules:

1. **Application/bootstrap** — flags, logging, lifecycle, dependency wiring.
2. **IRC adapter** — protocol connection, parser, reconnect, event normalisation and outbound messages.
3. **Bot core** — context, filters, command registry, longest-prefix dispatch, rewrite pipeline, poller lifecycle.
4. **Storage interface** — transactions, keyed/indexed collections, sequence counters, backup and fsck.
5. **Domain repositories** — karma, factoids, quotes, seen, URLs, stats, reminders, pushes, Markov.
6. **Drivers** — IRC event-to-domain orchestration and user-facing commands.
7. **Datetime/text utilities** — time zones, natural-language parsing, IRC formatting removal, lexer, URL detection, regex helpers.
8. **HTTP service** — short links, cache serving and optional OAuth endpoints.
9. **Integrations** — GitHub, Urban Dictionary, Minecraft, Pushbullet, flight API and optional LLM.

Keep domain logic testable without an IRC server. Keep the IRC adapter replaceable so the application can be exercised with synthetic IRC events.

## 11. Compatibility and acceptance test plan

A reimplementation is not complete until it passes tests in each group below.

### 11.1 Command routing
- Case-insensitive matching.
- Longest-prefix wins for overlapping prefixes.
- No command runs unless addressed (except private-message addressing).
- Bot nickname addressing is stripped from command text.
- Whitespace after prefix is compressed.
- Factoid insertion bypasses command dispatch.
- Help returns exact matching help, suggestions capped at ten, and unknown-command response.

### 11.2 Filters and lifecycle
- Ignored nicks are filtered case-insensitively.
- Events without a nick are still processed.
- Pollers start on CONNECTED and stop on DISCONNECTED.
- Shutdown cancels reminders and disconnects.
- Reconnect reloads pending reminders without duplicating them.

### 11.3 Storage
- Key byte encodings match the specified separators, endian and timestamp precision.
- Key validation rejects separator in names.
- Keyed Put/Get/All/Delete and nested bucket deletion.
- Indexed Put/Get/All/Match/Delete and replacement of existing ObjectId.
- BatchPut is atomic.
- Fsck repairs missing/stale index entries and removes validator-rejected duplicates.
- Sequence increment/set is durable and monotonic.

### 11.4 Feature scenarios
- Karma parsing for `thing++`, `thing--`, `(multi word thing)++`, Unicode subjects and invalid adjacency.
- Factoid creation, lookup, pseudo-random cycle, edit/delete, permissions, chance and metadata.
- Quote QID sequence, regex selection cycle and per-nick rate limit.
- Seen updates for every event and newest-per-action invariant.
- URL capture, regex search, random selection, short ID collision handling and cache size enforcement.
- Stats counters, weekday/hour histogram and top-ten order.
- Reminder scheduling, timezone conversion, listing/deletion, snooze, tells and reconnect recovery.
- Markov opt-in, transition counts, URL exclusion, generation termination and opt-out deletion.
- Utility command parsing and boundary cases.
- Optional integrations disabled/enabled with valid/invalid credentials.

### 11.5 End-to-end harness

The repository's integration test harness launches a local Ergo IRC daemon, builds the bot, connects the bot to the daemon and runs Go integration tests with an `integration` build tag. The shell script pins Ergo version 2.18.0 and verifies both archive and binary SHA-256 checksums. A language-independent equivalent should run a disposable local IRC server and assert protocol-visible responses. Tests should not require access to the production IRC network or live third-party credentials.

## 12. Known gaps / source-inspection backlog

The specification above is detailed enough to define the system's major architecture, persistence model and feature contracts, but several exact behaviours are not fully captured by the source excerpts inspected while preparing it. Before claiming byte-for-byte or transcript-level compatibility, inspect and record:

1. Server configuration, multiple-server connection setup, nick registration, TLS/SASL, reconnect/backoff and shutdown semantics in the server-set implementation.
2. The full rewrite-set and poller-set implementations, including ordering and error isolation.
3. The remaining methods in each driver: exact command parsing, responses, permission checks, regex substitutions, and state mutation.
4. Datetime parser grammar and its test corpus; timezone precedence and daylight-saving ambiguity handling.
5. Factoid addition grammar, lookup trigger grammar, chance semantics, read-only/owner rules and identifier replacement.
6. Quote rewrite syntax, fetch/delete response, rate-limit response and access-count behaviour.
7. Full URL scanner/extractor rules, redirect behaviour, cache response status and content-type handling.
8. Reminder tell delivery, list index lifetime, deletion authorisation, snooze duration defaults and reconnect behaviour.
9. Markov generation weighting, start-token selection, maximum chain length and corpus tagging rules.
10. Push credential schema and OAuth protocol, GitHub API target repository, Minecraft config keys, flight provider schema and Llama API contract.
11. Exact database backup naming/rotation and all fsck diagnostics.
12. All domain struct BSON tags and any migration assumptions for older database versions.

Treat these as explicit unresolved requirements, not permission to invent behaviour. The recommended process is to extract fixtures from the reference implementation (input IRC event → output messages + database before/after) and use them as language-neutral conformance tests.

## 13. Definition of done

A clean-room port is ready when:
- it builds and runs as a standalone process in the target language;
- it connects to an IRC test server and reconnects after disconnect;
- command addressing, matching, help, filters and rewrites conform;
- all core collections persist and survive restart;
- startup backup/fsck work;
- core features pass deterministic unit and integration tests;
- optional integrations fail closed when disabled or misconfigured;
- HTTP short links/cache work with security limits;
- no Go runtime or Go-specific package is required by the new implementation;
- unresolved items in Section 12 are either resolved with evidence or explicitly declared unsupported.

---
