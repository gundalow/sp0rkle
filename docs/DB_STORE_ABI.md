# Durable key/value storage ABI

The assembly storage adapter uses SQLite as the durable transactional engine. It stores opaque binary (path, key, value) tuples in a WITHOUT ROWID table with a composite primary key. BLOB ordering and equality are byte-exact. This is a storage-engine substitution, not a claim that the on-disk format is BoltDB-compatible; the Go reference's BSON value format and bucket/index semantics still need separate compatibility layers.

## Handle lifecycle

- db_store_open(path, handle_out): opens or creates a database, enables WAL journaling, and creates the schema. Returns 0 on success and -1 on failure.
- db_store_close(handle): closes the SQLite connection and returns SQLite's result code.
- db_store_begin(handle), db_store_commit(handle), db_store_rollback(handle): execute an immediate transaction boundary and return 0 on success or -1 on failure.

## Binary key/value operations

- db_store_put(handle, path, path_len, key, key_len, value, value_len): atomically upserts a BLOB value and returns 0 or -1.
- db_store_get(handle, path, path_len, key, key_len, out, capacity, out_len): copies a found value into caller-owned storage, writes its byte length to out_len, and returns 1 when found, 0 when absent, or -1 on error or insufficient capacity.
- db_store_delete(handle, path, path_len, key, key_len): deletes one exact tuple; absent keys are successful no-ops. Returns 0 or -1.

All byte lengths are explicit; embedded NUL, separator, and arbitrary binary bytes are preserved. Input buffers are copied by SQLite using SQLITE_TRANSIENT, so callers may release them after a call. The output buffer is caller-owned. A non-null pointer is required for path and key even when their lengths are zero; out_len is required for reads. A zero-length value is supported.

- db_store_sequence_next(handle, path, path_len, value_out): atomically increments a per-path signed 64-bit sequence, returning the new value through value_out (first value is 1).
- db_store_sequence_set(handle, path, path_len, value): sets the sequence to an exact signed 64-bit value; the next increment returns value + 1.

Sequence changes are single-statement atomic SQLite upserts and participate in an enclosing explicit transaction when one is active.

## Path representation

The adapter treats path as an opaque byte string. Use db_key_path_append to append each preceding key element as an eight-byte big-endian length followed by the element bytes; the final key element is passed as key. This preserves the reference K.B() distinction between nested bucket path and final key without conflating arbitrary binary element contents.

## Compatibility work still required

The current layer does not yet implement bucket enumeration, recursive bucket deletion, keyed/indexed collection policies, BSON marshal/unmarshal, index pointer maintenance, sequence allocation, fsck, or scheduled compressed backups. It also does not read existing BoltDB files. These remain explicit feature-parity tasks.
