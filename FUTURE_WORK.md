# Future Work: Code Review Findings and Improvements

This document outlines bugs, false assumptions, architectural issues, and modernization opportunities identified during the ultra-deep code review.

## Existing TODO Items

### soundcloud Integration
**What:** Integration with soundcloud to announce new tracks from followed bands/users.
**Why:** Currently lacking this feature which would require API use as they don't expose simple RSS feeds.
**How:** Implement a new driver or expand `netdriver` to use soundcloud API.
**Likelihood:** N/A (Feature Request)
**Severity:** Low

### Repeating Reminders
**What:** Support for daily, weekly, monthly reminders.
**Why:** Current reminder system only supports one-off reminders.
**How:** Update `reminddriver` and the underlying storage to handle recurrence rules.
**Likelihood:** N/A (Feature Request)
**Severity:** Medium

### Notify Driver
**What:** Split "tell" functionality out to a separate notify driver and add "ping me when x next says something".
**Why:** Better separation of concerns and added functionality for user notifications.
**How:** Create `notifydriver` and migrate relevant logic from `reminddriver`.
**Likelihood:** N/A (Architecture)
**Severity:** Low

### URL Search Configurable Constants
**What:** Make constants in `urlsearch` (bad url strings, max cache size, auto shorten limit) configurable.
**Why:** Hardcoded constants limit flexibility across different environments.
**How:** Move constants to flags or a configuration file.
**Likelihood:** High (They are currently hardcoded)
**Severity:** Low

### 404 Checking of Old URLs
**What:** Periodically check if stored URLs still exist.
**Why:** Avoid pointing users to dead links.
**How:** Implement a background poller in `urldriver` to HEAD request old URLs.
**Likelihood:** High (URLs go dead over time)
**Severity:** Low

### Multi-line Quotes
**What:** Support for adding and storing multi-line quotes.
**Why:** Current system likely handles single lines, missing "copypasta" or long conversations.
**How:** Implement `q begin` / `q end` logic to capture multiple lines and update storage to handle them.
**Likelihood:** High (Feature limitation)
**Severity:** Low

### Quote Stats
**What:** Track and display access counts for quotes.
**Why:** Allows identifying popular quotes and potential pruning of unused ones.
**How:** Increment a counter on each quote access and add a command to display stats.
**Likelihood:** High (Feature limitation)
**Severity:** Low

### Factoid Permissions
**What:** Implement an ownership and read-only system for factoids.
**Why:** Currently, anyone can modify or delete any factoid, leading to potential griefing.
**How:** Add an `owner` field to factoid schema and implement permission checks in `factdriver`.
**Likelihood:** High (Lack of authorization)
**Severity:** Medium

### Factoid Pruning
**What:** Prune 404'd F_URL factoids and utilize access counts to prune unseen factoids.
**Why:** Keeps the database clean and relevant.
**How:** Background poller for URL factoids and periodic cleanup based on access stats.
**Likelihood:** High (Database bloat)
**Severity:** Low

### Admin Commands and Permissions
**What:** Implementation of join/part/ignore commands with a permission system.
**Why:** Critical for bot management.
**How:** Implement an ACL system and restricted commands.
**Likelihood:** High (Feature limitation)
**Severity:** High

### Command Dispatch Layer in goirc
**What:** Push servemux-like command/handler dispatch up into a layer in goirc.
**Why:** Simplifies the bot's core and makes it more modular.
**How:** Refactor `bot/commandset.go` and potentially contribute back to `goirc`.
**Likelihood:** N/A (Architecture)
**Severity:** Low

### Help System Improvements
**What:** Look into godoc -> wiki.git dumping for help documentation.
**Why:** Manual help documentation is hard to maintain.
**How:** Automate help generation from code comments or dedicated help structures.
**Likelihood:** N/A (Maintenance)
**Severity:** Low

### Async Tasks and Polling
**What:** Revisit the polling / async tasks stuff.
**Why:** Current implementation is described as "terrible".
**How:** Use modern Go patterns, potentially `context`-aware worker pools.
**Likelihood:** High (Technical debt)
**Severity:** Medium

### Context Propagation
**What:** Use `context.Context` throughout the bot.
**Why:** Better cancellation and timeout management, especially now that `goirc` supports it.
**How:** Update all method signatures to accept `context.Context` and pass it down.
**Likelihood:** High (Outdated idiom)
**Severity:** Medium

### Dependency Injection
**What:** Use `google/wire` for proper dependency injection.
**Why:** Improves testability and manages complex dependencies between drivers and the core.
**How:** Refactor `Init` functions to use providers and injectors.
**Likelihood:** High (Architectural debt)
**Severity:** Medium

### BoltDB Migration Completion
**What:** Migrate `reminders` and `pushes` collections to BoltDB and move through migration states to `BOLT_ONLY`.
**Why:** Fully retire MongoDB dependency.
**How:** Complete the migration code in `db/migration.go` and update collections.
**Likelihood:** High (Incomplete migration)
**Severity:** High

## Initial Findings from `main.go`

### Deprecated `rand.Seed`
**What:** Usage of `rand.Seed(time.Now().UnixNano() * int64(os.Getpid()))`.
**Why:** `rand.Seed` is deprecated since Go 1.20. The global random generator is now automatically seeded.
**How:** Remove the `rand.Seed` call. For specific needs, use `rand.New(rand.NewSource(...))`.
**Likelihood:** 100% (Confirmed in code)
**Severity:** Low

### Lack of Graceful HTTP Shutdown
**What:** `go http.ListenAndServe(*httpPort, nil)` is used without any mechanism for graceful shutdown.
**Why:** When the bot shuts down, active HTTP connections might be dropped abruptly.
**How:** Use `http.Server` and its `Shutdown(ctx)` method, triggered by the same signal handler that shuts down the bot.
**Likelihood:** 100% (Confirmed in code)
**Severity:** Low

### Incomplete Signal Handling
**What:** `signal.Notify(sigint, syscall.SIGINT)` only listens for `SIGINT`.
**Why:** In many environments (like Docker/Kubernetes), `SIGTERM` is the standard signal for graceful shutdown.
**How:** Add `syscall.SIGTERM` to the `signal.Notify` call.
**Likelihood:** 100% (Confirmed in code)
**Severity:** Medium

### Potential Misuse of MongoDB Secret for Address
**What:** `db.Mongo.Init(bot.GetSecret(*mongoDB))`
**Why:** If `*mongoDB` is meant to be the server address (e.g., "localhost"), passing it to `bot.GetSecret` might be incorrect if `GetSecret` expects a key to look up a secret value, not the value itself.
**How:** Verify `bot.GetSecret` implementation and ensure `db.Mongo.Init` receives the correct address.
**Likelihood:** Medium (Depends on `bot.GetSecret` implementation)
**Severity:** Medium

### Re-exec Logic and Deferred Functions
**What:** `syscall.Exec` is used for re-executing the bot on rebuild.
**Why:** `syscall.Exec` replaces the current process, meaning deferred functions in the current goroutine (like `db.Bolt.Close()`) will not be executed unless called explicitly before `Exec`.
**How:** Ensure all critical cleanup is done explicitly before `syscall.Exec`.
**Likelihood:** 100% (Acknowledged in code comments)
**Severity:** Medium

## Core Bot Logic Findings (`bot/`)

### Case Sensitivity in Command Matching
**What:** `commandSet.match` uses `strings.HasPrefix(txt, prefix)` which is case-sensitive.
**Why:** IRC commands are traditionally case-insensitive. If a user types `.HELP` instead of `.help`, the command might not be recognized if the prefix was registered as lowercase. A test for this would fail to match commands with different casing.
**How:** Normalize both `txt` and `prefix` to lowercase before comparison in `match()`.
**Likelihood:** High
**Severity:** Low

### Potential Panics on Empty or Short Input
**What:** Several handlers (`ignore`, `unignore`, `migrate`, `check_rebuilder`) access slices from `strings.Fields()` by index without checking the length.
**Why:** If a user sends a command with no arguments or fewer arguments than expected, the bot will panic and potentially crash (or be caught by `unfail` and disconnected). A test for this would fail (panic).
**How:** Always check `len(fields)` before accessing indices.
**Code Snippet:**
```go
fields := strings.Fields(ctx.Text())
if len(fields) < 1 {
    return
}
nick := strings.ToLower(fields[0])
```
**Likelihood:** High
**Severity:** Medium

### Lack of Permission Checks for Critical Commands
**What:** `ignore` and `unignore` commands can be used by any user.
**Why:** A malicious user could make the bot ignore its own owner or other administrators, effectively locking them out of bot control. A test for this would fail to prevent unauthorized access.
**How:** Implement a permission check (e.g., using the `rebuilder` logic or a new admin list) before executing these commands.
**Likelihood:** 100%
**Severity:** High

### Deprecated `ioutil` Usage
**What:** `bot/bot.go` uses `ioutil.ReadFile`.
**Why:** `ioutil` is deprecated since Go 1.16.
**How:** Replace `ioutil.ReadFile` with `os.ReadFile`.
**Likelihood:** 100%
**Severity:** Low (Maintenance)

### Outdated Rebuild Logic
**What:** `rebuild` handler uses `go get -u github.com/fluffle/sp0rkle`.
**Why:** `go get` for installing binaries is deprecated in favor of `go install`. Furthermore, in a module-aware environment, this might not behave as expected or might fail if the environment isn't set up for it.
**How:** Use `go build` or `go install` and ensure the bot is running in an environment where it can update its own source and rebuild.
**Likelihood:** High
**Severity:** Medium

### Global Bot Singleton and Testability
**What:** The `bot` variable is a global singleton, and many functions (`Handle`, `Command`, etc.) rely on it.
**Why:** Makes unit testing extremely difficult as state is shared and initialization is global. It also prevents running multiple bot instances in the same process.
**How:** Refactor the bot to use an instance-based approach. Pass the bot instance to drivers and handlers.
**Likelihood:** 100%
**Severity:** Medium (Architectural)

### Race Conditions in `pollerset`
**What:** `ps.contexts()` is called from a goroutine while `Handle` or `Add` might be modifying `ps.conns`.
**Why:** Although `ps.contexts()` uses `RLock`, `Handle` uses `Lock`. If `Handle` is holding `Lock` and calls `startOne`, which spawns a goroutine that immediately calls `ps.contexts()`, that goroutine will block until `Handle` releases the lock. While not a deadlock, it's a potential source of subtle issues if more complex interactions are added.
**How:** Pass the necessary contexts directly to `startOne` or ensure the locking strategy is simplified.
**Likelihood:** Medium
**Severity:** Low

## Database and Collections Findings (`db/`, `collections/`)

### Potential Data Loss in BoltDB Backups
**What:** `boltDatabase.doBackup` ignores the error from the deferred `fz.Close()` call.
**Why:** Closing a `gzip.Writer` flushes remaining data and writes the gzip footer. If this fails (e.g., due to disk full), the backup file will be incomplete and invalid.
**How:** Handle the error from `fz.Close()` explicitly, or use a named return variable to capture the error from the deferred function.
**Code Snippet:**
```go
defer func() {
    if cerr := fz.Close(); cerr != nil && err == nil {
        err = cerr
    }
}()
```
**Likelihood:** Medium
**Severity:** Medium

### False Assumption: Regex Matches Always String Fields
**What:** `keyedBucket.Match` assumes that the field being matched against is a string.
**Why:** It calls `cev.FieldByName(field).String()`. If the field is an integer, boolean, or other type, `reflect.Value.String()` returns a string representation like `<int Value>`, which is likely not what the user intended to match against with a regex. If the field doesn't exist, it might panic if not checked.
**How:** Explicitly check the kind of the field and handle accordingly, or document that `Match` only supports string fields.
**Likelihood:** High
**Severity:** Low

### Case-Insensitivity Forced on All Regex Matches
**What:** `keyedBucket.Match` prepends `(?i)` to all regex patterns.
**Why:** This forces case-insensitivity for all matches, which might not be desirable for all collections or use cases.
**How:** Allow the caller to specify whether they want case-insensitivity, or let them include `(?i)` in their own regex if needed.
**Likelihood:** 100%
**Severity:** Low

### Potential Overflow in BoltDB Sequences
**What:** `keyedBucket.Next` returns an `int`, while BoltDB sequences are `uint64`.
**Why:** On 32-bit systems, `int` is 32 bits. If the sequence exceeds $2^{31}-1$, the return value will overflow and become negative.
**How:** Change the return type of `Next` to `uint64` or `int64`.
**Likelihood:** Low (Depends on number of items and architecture)
**Severity:** Medium

### Ignoring `ErrTxNotWritable` in Config Get
**What:** `namespace.get` ignores `bbolt.ErrTxNotWritable`.
**Why:** `Get` operations should ideally be performed in a read-only transaction (`View`). If `Get` returns `ErrTxNotWritable`, it implies the transaction was somehow opened as writable but is being used where it's not expected, or vice-versa. Silently ignoring it might hide underlying architectural issues.
**How:** Investigate why this error was being ignored and ensure proper transaction usage.
**Likelihood:** 100% (Confirmed in code)
**Severity:** Low

### Debug `println` in Unified Diff
**What:** `Unified` function in `util/diff/patience.go` contains `println(len(diffs))`.
**Why:** This prints to standard output on every diff operation, which is unprofessional and might clutter logs.
**How:** Remove the `println` or replace it with a proper logging call if needed.
**Likelihood:** 100%
**Severity:** Low

## Driver Findings (`drivers/`)

### Widespread Race Conditions in Shared Maps
**What:** Multiple drivers (`calcdriver`, `reminddriver`, `urldriver`) use shared maps without mutex protection.
**Why:** IRC handlers are executed in goroutines. If multiple messages arrive simultaneously, concurrent access to these maps (e.g., `results`, `running`, `finished`, `listed`, `lastseen`) will cause a race condition, potentially leading to crashes or corrupted state. A test running with `-race` would fail for this.
**How:** Protect all shared map accesses with `sync.Mutex` or `sync.RWMutex`.
**Likelihood:** High
**Severity:** High

### SSRF Vulnerability in `urldriver`
**What:** `urldriver.Cache` performs `http.Get` on user-provided URLs.
**Why:** A malicious user could provide URLs pointing to internal services (e.g., `http://localhost:8080/admin`) to perform internal port scanning or access restricted internal data through the bot.
**How:** Implement a check to ensure the URL doesn't resolve to a private or loopback IP address.
**Likelihood:** Medium
**Severity:** High

### Byte Length vs. Character Count
**What:** `calcdriver.length` uses `len(ctx.Text())`.
**Why:** In Go, `len()` on a string returns the number of bytes, not the number of Unicode characters (runes). For multi-byte characters, this will return an incorrect "length" from a user's perspective.
**How:** Use `utf8.RuneCountInString(ctx.Text())`.
**Likelihood:** 100%
**Severity:** Low

### Fragile Time Parsing in `calcdriver`
**What:** `calcdriver.date` uses `strings.Index(tstr, "in ")` to identify timezones.
**Why:** If a user provides a time string like "5 in minutes", it will incorrectly identify "minutes" as the timezone.
**How:** Use a more robust parsing strategy or a dedicated regex to separate the time string from the timezone suffix.
**Likelihood:** Medium
**Severity:** Low

### Suboptimal Reminder Cancellation Handling
**What:** `reminddriver.Remind` goroutine waits for `<-c.Done()` but only acts if `c.Err()` is `DeadlineExceeded`.
**Why:** If a reminder is manually forgotten/cancelled, the goroutine still fires and does nothing. While not a bug per se, it's less clean than it could be. More importantly, it doesn't handle other context errors.
**How:** Check for manual cancellation explicitly and potentially log it or perform cleanup.
**Likelihood:** 100%
**Severity:** Low (Technical Debt)

## Utility Findings (`util/`)

### Limited Backtracking in Lexer
**What:** `util.Lexer.Rewind()` only undoes the very last `Next()` or `Scan()` operation.
**Why:** If a caller performs multiple lexing steps and then realizes they need to backtrack further, `Rewind()` will not be able to return to the original starting point.
**How:** Implement a more robust position stack for the lexer if deep backtracking is required, or ensure callers are aware of this limitation.
**Likelihood:** High
**Severity:** Low

### Date Rolling in Relative DateTime Parsing
**What:** The `datetime` utility uses Go's `time.AddDate(y, m, d)`.
**Why:** `AddDate` can produce unexpected results when adding months to the end of a month. For example, adding 1 month to January 31st results in March 2nd or 3rd (depending on leap year) because February 31st doesn't exist. This might be surprising to users setting reminders.
**How:** Document this behavior or implement "end-of-month" aware date addition if it's considered a bug for reminders.
**Likelihood:** Medium
**Severity:** Low

### Potential Panic in `util.Lexer.Number`
**What:** `util.Lexer.Number` calls `l.Input[s:l.pos]` without checking if `s` and `l.pos` are within bounds or in the correct order.
**Why:** While internal logic seems to keep them in sync, a malformed state could lead to a slice out of bounds panic.
**How:** Add safety checks before slicing.
**Likelihood:** Low
**Severity:** Medium

## Go Modernization Opportunities

### Use `any` Instead of `interface{}`
**What:** The codebase uses `interface{}` extensively.
**Why:** Go 1.18 introduced `any` as an alias for `interface{}`, which is more concise and idiomatic in modern Go.
**How:** Run `gofmt -w -r 'interface{} -> any' .`
**Likelihood:** 100%
**Severity:** Low (Readability)

### Generics for Collection Abstractions
**What:** The `db` and `collections` packages use reflection and `interface{}`/`any` for generic data handling.
**Why:** Modern Go generics (introduced in 1.18) allow for type-safe collections and database abstractions, reducing the need for reflection and making the code more robust and performant.
**How:** Refactor `Collection` and `db.C` to be generic: `Collection[T any]`.
**Likelihood:** High
**Severity:** Medium (Architectural)

### Structured Logging with `log/slog`
**What:** The bot uses a custom `golog` package.
**Why:** Go 1.21 introduced `log/slog` for structured logging. Using a standard, structured logger would improve log searchability and integration with modern observability tools.
**How:** Replace `golog` with `log/slog`.
**Likelihood:** High
**Severity:** Low (Maintenance)

### Consistent Context Propagation
**What:** Many functions and methods do not accept or propagate `context.Context`.
**Why:** Context is essential for managing timeouts and cancellations, especially in a network-heavy application like an IRC bot.
**How:** Update all method signatures to accept `ctx context.Context` as the first argument and pass it through to all network and database calls.
**Likelihood:** 100%
**Severity:** Medium

### Replacement of Deprecated `ioutil`
**What:** `ioutil.ReadFile` and `ioutil.ReadAll` are still used in some places.
**Why:** These were deprecated in Go 1.16 in favor of equivalent functions in the `os` and `io` packages.
**How:** Replace `ioutil.ReadFile` with `os.ReadFile` and `ioutil.ReadAll` with `io.ReadAll`.
**Likelihood:** 100%
**Severity:** Low (Maintenance)
