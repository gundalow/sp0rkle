# IRC context helper ABI

`bot_strip_address_prefix(text, text_len, nick, nick_len, out_start, out_len)`

Detects the original bot's addressed-message syntax: the message must start
with the bot nick (ASCII-case-insensitive), followed immediately by one of
`: ; , > -`. The helper returns 1 on a match and 0 otherwise. On a match,
`out_start/out_len` identify the remainder after the nick and delimiter,
with leading and trailing ASCII whitespace removed. On no match both outputs
are zero. Input is never modified and no memory is allocated.

The helper deliberately does not decide whether a PRIVMSG target is the bot
nick; the caller should treat private messages as addressed independently.
It also does not interpret Unicode whitespace; the current low-level helper
trims ASCII space and horizontal/vertical tab through carriage return.


## PRIVMSG preparation

`bot_context_prepare_privmsg(text, text_len, botnick, nick_len, target,
target_len)` implements the PRIVMSG portion of the reference
`newContext` operation. It returns a 16-byte C structure:

- `start` (`size_t`): offset into the original input buffer
- `len` (`uint32_t`): length of the resulting context text
- `addressed` (`uint32_t`): 1 when the message addresses the bot, otherwise 0

The helper trims outer ASCII whitespace, removes an optional botnick prefix
followed by one of `: ; , > -`, and trims whitespace around the remainder.
A matched prefix marks the message addressed. If there is no prefix, the
message is addressed when `target` exactly equals `botnick` byte-for-byte,
matching the reference's direct string comparison for private messages.

The result structure is returned in the System V AMD64 `RAX:RDX` pair.
Unicode whitespace trimming remains a known difference from Go's
`strings.TrimSpace`.


## Rewrite pipeline

`bot_rewrite_apply(entries, count, input, input_len, scratch_a, scratch_b,
capacity, out_len)` applies registered rewrite callbacks in registration
order. A rewriter entry is 16 bytes: callback pointer at offset 0 and opaque
context pointer at offset 8. Each callback has the C ABI:

`ssize_t rewrite(ctx, input, input_len, output, output_capacity)`

A callback returns the number of output bytes, or a negative value on failure.
It must not write more than `output_capacity - 1` bytes. The wrapper adds the
terminating NUL and passes each result to the next callback. The two distinct
caller-owned scratch buffers are alternated, and each must have at least
`capacity` bytes. Neither scratch buffer may overlap the input or the other
scratch buffer. `out_len` is required. The function returns the final string
pointer, or NULL if a callback fails or produces an invalid length. With no
callbacks, it returns the original input pointer and length unchanged.

This preserves the Go `RewriteSet` registration-order semantics. The caller
must serialize access to mutable callback state if needed; the assembly
pipeline itself does not add locking.


## Context output / send wrappers

`bot_context_emit(const struct bot_emit_request *)` uses a 112-byte request containing a send callback and opaque context, operation (1 = PRIVMSG, 2 = ACTION, 3 = TOPIC), target and text pointer/length pairs, optional rewrite entries/count, two scratch buffers/capacity, and a 32-bit `apply_rewrites` flag at offset 96.

The callback ABI is `int send(ctx, operation, target, target_len, text, text_len)`. Its return value is propagated. A null callback or rewrite failure returns -1. When `apply_rewrites` is nonzero, the ordered rewrite pipeline runs before the callback. Use this for Context `Reply` (PRIVMSG) and `Do` (ACTION). Set it to zero for explicit `Privmsg`, `Action`, and `Topic`, matching Go's rewrite bypass. A TOPIC query can use zero-length text.

`bot_context_prefix_nick(nick, nick_len, text, text_len, out, capacity)` constructs the `nick: text` payload used by `ReplyN`; it returns the byte length or -1 when invalid or too small. The caller then sends that buffer through `bot_context_emit` with operation PRIVMSG and rewriting enabled. This keeps formatting independent of transport and avoids hidden allocation.

`bot_context_resolve_target(target, target_len, nick, nick_len)` returns a `{ptr,len}` string view in `RAX:RDX`, matching goirc `Line.Target()`: channel targets beginning with `#`, `&`, `+`, or `!` are retained; private-message targets resolve to the sender nick. The caller can pass this view as the target in `bot_context_emit` for Reply/Do.
