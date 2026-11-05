# Database key encoding ABI

This module implements the reference database's byte-level key element encoding. It does not implement Bolt buckets, BSON values, transactions or collection scans; those remain separate storage work.

- `db_key_validate_name(name, name_len)`: returns 0 unless the name is null or contains the unit-separator byte `0x1f`, in which case it returns -1.
- `db_key_encode_string(name, name_len, value, value_len, out, capacity)`: writes `name || 0x1f || value`.
- `db_key_encode_u64(name, name_len, value, out, capacity)`: writes `name || 0x1f || value`, with the uint64 encoded as exactly eight big-endian bytes so lexicographic ordering follows numeric ordering.
- `db_key_encode_bool(name, name_len, value, out, capacity)`: writes `name || 0x1f || 0xff` for true and `name || 0x1f || 0x00` for false.

Each encoder returns the number of bytes written or -1. Capacity is checked before output is modified. Names cannot contain `0x1f`; values are not restricted and may contain any byte. The caller owns all buffers and must supply non-overlapping input/output regions. Timestamp elements use the uint64 encoder with Unix milliseconds; ObjectId elements use the string encoder with the fixed name `_id` and exactly 12 binary bytes.
