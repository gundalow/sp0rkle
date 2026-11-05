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
