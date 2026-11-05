# IRC-to-Context adapter ABI

`bot_irc_privmsg_views(line, line_len, parsed_message, out)` extracts the
byte views needed to construct a bot Context from a user-originated IRC
`PRIVMSG`.

The 48-byte output structure contains three pointer/length pairs:

- offset 0: sender nick pointer; offset 8: nick length
- offset 16: message target pointer; offset 24: target length
- offset 32: message text pointer; offset 40: text length

All pointers reference the original IRC line. The adapter does not allocate,
copy, normalize, or modify input. It requires a `PRIVMSG` command, at least
two parameters, a valid prefix containing a nick followed by `!` or `@`,
and in-bounds prefix/command/parameter slices.

Return values are 1 for a valid user-originated PRIVMSG, 0 for another command
or a server/non-user prefix, and -1 for invalid arguments or malformed
structure offsets. After extraction, pass the text and target views to
`bot_context_prepare_privmsg`; pass the target and sender views to
`bot_context_resolve_target` to obtain the reply destination. This keeps
IRC framing/parsing separate from Context policy and output.


## Prepared Context adapter

`bot_irc_privmsg_context(line, line_len, parsed_message, botnick,
botnick_len, out)` composes extraction, `bot_context_prepare_privmsg`, and
`bot_context_resolve_target` into one call.

Its 72-byte output structure is:

- offset 0: sender nick pointer; offset 8: nick length
- offset 16: original IRC target pointer; offset 24: target length
- offset 32: prepared body pointer; offset 40: body length
- offset 48: reply destination pointer; offset 56: reply destination length
- offset 64: addressed flag (32-bit; remaining bytes reserved)

The prepared body has outer ASCII whitespace removed and an optional
case-insensitive `botnick` address prefix removed. The addressed flag is true
for a recognized address prefix or an exact private-message target match.
Channel targets (`#`, `&`, `+`, `!`) remain the reply destination;
private-message targets resolve to the sender nick.

All views still reference the caller-owned IRC line. The caller must keep that
line alive while using the Context. The bot nick must be a valid pointer for
its supplied length. Return values match the lower-level extractor: 1 for a
user PRIVMSG, 0 for a non-context event, and -1 for malformed input.
