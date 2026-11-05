# Command registry ABI

Target: x86-64 Linux, NASM ELF64, System V AMD64 ABI.

## Command prefix matching

`bot_command_match(entries, count, text, text_len, matched_prefix_len)`

- RDI: pointer to the first entry.
- ESI: number of entries.
- RDX: message text byte pointer.
- RCX: message text byte length.
- R8: writable `size_t*` for the matched prefix length (may be NULL).
- RAX: pointer to the selected entry, or NULL.

Each entry is 32 bytes:

| Offset | Field |
|---:|---|
| 0 | prefix pointer |
| 8 | prefix byte length (uint64) |
| 16 | opaque handler pointer |
| 24 | help string pointer |

Matching is ASCII-case-insensitive and byte-oriented. A prefix matches at
the beginning of the supplied text. The longest matching prefix wins;
equal-length ties retain registration order. Empty prefixes never match.
The helper does not allocate, mutate the registry, trim whitespace, check
whether the message addressed the bot, or execute handlers. The caller owns
all entry and string storage and must keep it valid for the duration of the
call. The routine is read-only; synchronisation of registry mutation remains
the caller's responsibility.

## Command argument normalization

`bot_command_normalize_args(input, input_len, output, output_capacity)`

- RDI: input byte pointer.
- RSI: input byte length.
- RDX: output buffer.
- RCX: output capacity, including space for the terminating NUL.
- RAX: normalized byte length, or -1 on invalid/insufficient output storage.

The helper trims leading and trailing ASCII whitespace (space and bytes 9
through 13) and replaces each internal run with one ASCII space. Empty or
whitespace-only input produces an empty NUL-terminated string. The input and
output buffers must not overlap. The input is not modified. On failure, the
helper writes an empty string when a non-null output buffer with nonzero
capacity is available.
