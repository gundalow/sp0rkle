# Karma IRC event adapter ABI

`karma_irc_event_callback(ctx, line, line_len, parsed_message)` implements the callback shape used by `irc_event_dispatch`. It extracts a user PRIVMSG, recognises a CTCP ACTION wrapper, parses Karma annotations, obtains a realtime Unix-millisecond timestamp, and applies annotations through the SQLite persistence callbacks.

The caller-owned 56-byte context contains: offset 0 storage-context pointer; offset 8 annotation-array pointer; offset 16 annotation capacity in entries; offset 24 normalized-key scratch pointer; offset 32 key capacity; offset 40 88-byte record scratch pointer.

Each annotation entry is 16 bytes: uint64 text offset, uint32 subject length, int32 delta. All pointers and buffers remain caller-owned.

The callback returns the number of annotations applied, zero for non-user messages or no annotations, or -1 on malformed input, clock failure, storage failure or invalid annotation data. The generic event dispatcher ignores callback return values, so applications needing diagnostics should wrap the callback with logging.

Unicode subject classification, duplicate/self-vote policy and exact transcript responses remain to be matched against the reference tests.