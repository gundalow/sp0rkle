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
