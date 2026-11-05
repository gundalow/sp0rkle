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
