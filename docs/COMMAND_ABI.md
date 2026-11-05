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
