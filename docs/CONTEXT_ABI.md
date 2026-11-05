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
target_len, out_start, out_len, out_addressed)` implements the PRIVMSG
portion of the reference `newContext` operation.

It trims outer ASCII whitespace from the input, then applies
`bot_strip_address_prefix` to the trimmed text. A matched prefix marks the
message addressed and returns the remaining text offsets relative to the
original input buffer. If there is no prefix, it returns the trimmed full
text. In that case, the message is also addressed when `target` exactly
equals `botnick` byte-for-byte, matching the reference's direct string
comparison for private messages.

All three output pointers are required. The function returns zero on success
and -1 when an output pointer is null. Unicode whitespace trimming remains a
known difference from Go's `strings.TrimSpace`.
