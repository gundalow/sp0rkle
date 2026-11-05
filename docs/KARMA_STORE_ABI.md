# Karma SQLite persistence adapter

The Karma feature now has a concrete SQLite persistence bridge. It connects the existing annotation parser and record mutation routine to the durable binary store, using BSON-compatible records and the same final key element as the reference keyed collection.

## Context ABI

The caller allocates a 104-byte context:

| Offset | Type | Meaning |
|---:|---|---|
| 0 | pointer | SQLite database handle |
| 8 | pointer | BSON scratch buffer |
| 16 | uint64 | BSON scratch capacity |
| 24 | pointer | encoded key scratch buffer |
| 32 | uint64 | encoded key capacity |
| 40 | pointer | decoded subject buffer |
| 48 | uint64 | subject capacity |
| 56 | pointer | decoded key buffer |
| 64 | uint64 | key capacity |
| 72 | pointer | decoded upvoter buffer |
| 80 | uint64 | upvoter capacity |
| 88 | pointer | decoded downvoter buffer |
| 96 | uint64 | downvoter capacity |

All buffers remain caller-owned and must remain valid for the duration of each callback. The SQLite adapter copies encoded key and BSON bytes into SQLite before returning. Decoded strings are views into the supplied context buffers and are overwritten by the next lookup.

## Callback ABI

- `karma_sqlite_lookup(ctx, key, key_len, record_out)`: returns 1 when found, 0 when absent, or -1 on storage/decode failure. It encodes the key as `key\x1f<normalized-key>`, reads the BSON value from the `karma` collection path and decodes it into record_out.
- `karma_sqlite_put(ctx, record)`: BSON-encodes the record and upserts it into the `karma` collection. Returns 0 on success or -1 on failure.

These callbacks can be passed directly to `karma_apply_annotations`. Each annotation is committed as an independent upsert unless the caller wraps the sequence in an explicit database transaction. A later annotation failure does not undo earlier writes unless that outer transaction is rolled back.

## BSON representation

The adapter encodes fields in the Go struct order: `subject`, `key`, `score`, `votes`, `upvoter`, `upvtime`, `downvoter`, `downvtime`. Strings use BSON UTF-8 string elements, integer values use BSON int32 when representable and int64 otherwise, and timestamps use BSON datetime milliseconds. Zero timestamps use the Go BSON zero-time sentinel. The decoder validates document length, field order/types, string bounds and output capacities.

This is a schema-specific BSON codec, not yet the complete general-purpose BSON implementation needed by every collection.
