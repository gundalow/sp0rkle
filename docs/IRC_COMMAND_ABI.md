# IRC-to-command pipeline ABI

`bot_irc_privmsg_command_process(request)` connects a parsed IRC user
PRIVMSG to the existing bot command-processing pipeline. It composes
`bot_irc_privmsg_context`, raw-body factoid detection, nick filters and
`bot_command_process`. It does not execute the opaque command handler; the
caller receives that handler pointer and remains responsible for invoking it.

The request structure is 96 bytes:

| Offset | Field | Type |
|---:|---|---|
| 0 | original IRC line | pointer |
| 8 | original IRC line length | size_t |
| 16 | parsed IRC message | pointer |
| 24 | bot nickname | pointer |
| 32 | bot nickname length | size_t |
| 40 | filter entries | pointer to 16-byte filter entries |
| 48 | filter count | uint32 |
| 56 | command entries | pointer to 32-byte command entries |
| 64 | command count | uint32 |
| 72 | output normalized arguments | char pointer |
| 80 | output capacity including NUL | size_t |
| 88 | output handler | pointer-to-pointer |

For a user-originated PRIVMSG, the adapter prepares the body and addressed
flag, resolves the sender nick, evaluates the factoid-addition predicate on
the raw message body, then calls `bot_command_process`. Thus ignored nicks
are rejected before command matching; unaddressed messages and factoid
additions are not dispatched. Private messages are treated as addressed by
the Context adapter. Channel messages require an explicit bot-nick address.

Return values are 1 when a handler is selected, 0 for non-PRIVMSG,
non-user-originated input, filtered input, unaddressed input, factoid
addition, or no matching command, and -1 for invalid input/output state.
The output argument buffer and handler pointer are cleared on non-dispatch
when their storage is valid. The original IRC line and all registry/filter
storage remain caller-owned and must stay valid during the call.

The adapter uses the raw PRIVMSG body for factoid detection (not the entire
IRC frame), matching the command-processing contract. It is byte-oriented
and inherits the ASCII whitespace/case-folding limits documented in the
Context and command ABI documents.
