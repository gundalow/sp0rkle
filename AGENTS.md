# Agent Guide for sp0rkle

This guide provides information for AI agents working on the sp0rkle codebase.

## Coding Style

- **Language**: Go.
- **Formatting**: Follow standard Go formatting (`gofmt`). Use tabs for indentation.
- **Logging**: Use the `github.com/fluffle/golog/logging` package for all logging.
- **Error Handling**: Follow standard Go error handling patterns.
- **Conventions**:
    - Multi-word commands should be supported case-insensitively.
    - All command registrations should be done using `bot.Command`.
    - Use `bot.Context` for interacting with IRC, but be aware of the planned migration to standard `context.Context`.

## Testing Strategy

- **Test Files**: Always include `_test.go` files for new functionality.
- **Patterns**: Prefer table-driven tests.
- **Running Tests**: Use `go test ./...` from the root directory to run all tests.
- **Mocks**: Some packages use `github.com/golang/mock` for mocking IRC connections and other interfaces.

## Persistence

- The project uses a mix of MongoDB (via `gopkg.in/mgo.v2`) and BoltDB (via `go.etcd.io/bbolt`).
- There is an ongoing effort to migrate from MongoDB to BoltDB.
- Check `bot/bot.go` for migration logic.

## Command Set

- Command matching is case-insensitive.
- Command prefixes are stored in lowercase in the `CommandSet`.
- Matching uses the longest prefix that matches the input case-insensitively.
- Arguments passed to command handlers preserve their original case.
