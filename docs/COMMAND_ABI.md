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


## Command dispatch orchestration

`bot_command_dispatch(entries, count, text, text_len, addressed,
factoid_addition, out_args, out_capacity, out_handler)`

The helper combines command selection and the addressed/factoid gates. It
expects `text` to be the already-trimmed context message text; filters and
context construction remain the caller's responsibility.

- `addressed` must be nonzero for dispatch to proceed.
- `factoid_addition` is a caller-computed boolean. The caller must evaluate
  the original IRC line text with the reference factoid-addition predicate;
  such input is bypassed. This is separate from the trimmed context text used
  for command matching.
- The longest matching command prefix is selected using
  `bot_command_match`.
- The selected entry's opaque handler pointer is written to `out_handler`.
- The text after the matched prefix is passed through
  `bot_command_normalize_args` and written to `out_args`.

Return values: 1 means a handler was selected; 0 means not addressed, a
factoid addition, or no matching command; -1 means invalid output arguments
or insufficient output capacity. On non-dispatch, the output handler is
cleared and the argument buffer is empty when valid output storage is
provided. The helper does not execute the handler. The caller must apply the
line-filter pipeline before invoking it.

The caller is responsible for evaluating factoid-addition syntax against the
unmodified IRC line text before calling dispatch.


## Factoid-addition detector

`bot_is_factoid_addition(text, text_len)` returns 1 when the explicit-length
text contains either `:is` or `:=`, using ASCII case-insensitive matching,
and 0 otherwise. This mirrors the reference `util.IsFactoidAddition`
predicate. Call it with the original IRC line text, before context text is
trimmed or the addressed nickname is removed. Pass its result as the
`factoid_addition` argument to `bot_command_dispatch`.


## Help lookup

`bot_command_help_text(entries, count, text, text_len)` returns the help
string pointer from the entry with the longest matching prefix, using the
same case-insensitive matching and tie behaviour as
`bot_command_match`. It returns NULL when no prefix matches. Empty-input
wiki response, candidate suggestions, and final response formatting remain
the responsibility of the help command handler.


## Help candidate suggestions

`bot_command_possible(entries, count, text, text_len, out, capacity)`
returns up to ten prefix pointers whose registered prefix contains at least
one whitespace-delimited input word, case-insensitively. Each registered
prefix is emitted at most once, in registration order. The output capacity
may further limit the result count. A zero capacity returns zero without
requiring an output pointer; a nonzero capacity with a null output pointer
returns -1. The implementation uses ASCII whitespace and ASCII case folding,
whereas Go's `strings.Fields` and `strings.ToLower` are Unicode-aware.


## Filtered command-processing entry point

`bot_command_process(const struct bot_command_request *request)` applies the
filter pipeline before invoking `bot_command_dispatch`. The request structure
is 96 bytes:

| Offset | Field | Type |
|---:|---|---|
| 0 | filters | pointer to 16-byte filter entries |
| 8 | filter_count | uint32 |
| 16 | source nick | pointer |
| 24 | source nick length | size_t |
| 32 | command entries | pointer to 32-byte entries |
| 40 | command_count | uint32 |
| 48 | context text | pointer |
| 56 | context text length | size_t |
| 64 | addressed | uint32 |
| 68 | factoid_addition | uint32 |
| 72 | output arguments | char pointer |
| 80 | output capacity | size_t |
| 88 | output handler | pointer-to-pointer |

The caller supplies a fully constructed context text and computes
`factoid_addition` against the original IRC line. The function evaluates
filters first; on rejection it returns 0 and clears valid output buffers.
Otherwise it forwards the dispatch result (1, 0, or -1). The request pointer
must be non-null and all referenced structures must remain valid for the call.
