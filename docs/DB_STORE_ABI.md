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

- db_store_bucket_ensure(handle, path, path_len): creates one exact bucket path; parent paths are the caller's responsibility.
- db_store_bucket_exists(handle, path, path_len): returns 1 if the exact path exists, 0 if absent, or -1 on error.
- db_store_bucket_delete(handle, path, path_len): recursively deletes values, sequences, and bucket records whose paths begin with the supplied non-empty path. The root bucket cannot be deleted. A SQLite savepoint makes the operation atomic and allows it inside an outer transaction.

- db_store_scan_open(handle, path, path_len, statement_out): opens a read cursor over the exact bucket path, ordered by bytewise key.
- db_store_scan_next(statement, key_out, key_capacity, key_len_out, value_out, value_capacity, value_len_out): copies the next row into caller buffers and returns 1 for a row, 0 at end, or -1 on error/capacity failure.
- db_store_scan_close(statement): finalizes the cursor.

- db_store_put_batch(handle, entries, count): atomically upserts a batch of 48-byte entries (path pointer/length, key pointer/length, value pointer/length). It uses a SQLite savepoint, so it composes with an outer transaction. Any invalid entry rolls back the entire batch.

- db_store_scan_tree_open(handle, prefix, prefix_len, statement_out): opens a bytewise-ordered cursor over values in the exact bucket path and all descendant paths.
- db_store_scan_tree_next(statement, descriptor): copies the next row's path, key and value into caller buffers. The 72-byte descriptor contains pointer/capacity/length-output triples for path, key and value at offsets 0/8/16, 24/32/40 and 48/56/64. Returns 1 for a row, 0 at end, or -1 on error/capacity failure.
- db_store_scan_close(statement): finalizes either exact-bucket or subtree cursors.

- db_store_backup(source_handle, destination_path): writes a consistent point-in-time SQLite snapshot using the online backup API. The destination is opened/created and closed by the function; periodic scheduling, compression, rotation and secure directory policy belong to the application layer.

- db_store_integrity_check(handle): runs SQLite PRAGMA integrity_check and returns 0 only when the result is exactly `ok`; returns -1 on corruption or database errors.

## Path representation

The adapter treats path as an opaque byte string. Use db_key_path_append to append each preceding key element as an eight-byte big-endian length followed by the element bytes; the final key element is passed as key. This preserves the reference K.B() distinction between nested bucket path and final key without conflating arbitrary binary element contents.

## Compatibility work still required

The current layer supports ordered scans of one exact bucket, but does not yet implement keyed/indexed collection policies, BSON marshal/unmarshal, index pointer maintenance, fsck, or scheduled compressed backup rotation. It also does not read existing BoltDB files. These remain explicit feature-parity tasks.
