# Karma record ABI

`karma_key_normalize(input, input_len, output, capacity)` creates the persistent lookup key by ASCII-lowercasing A–Z and preserving all other bytes. Capacity includes the NUL terminator. Returns the byte length or -1. Unicode case folding is not implemented yet.

`karma_record_apply(record, delta, voter, voter_len, unix_ms)` mutates the caller-owned 88-byte record. The layout is: subject pointer/length at 0/8, normalized key pointer at 16, signed score at 24, vote count at 32, last upvoter pointer/length/time at 40/48/56, and last downvoter pointer/length/time at 64/72/80. Delta must be +1 or -1. A valid vote increments the vote count, changes score by delta, and updates only the corresponding last-voter fields. Signed score and unsigned vote overflow are rejected without mutation. Voter and subject pointers remain caller-owned; timestamps are Unix milliseconds.
