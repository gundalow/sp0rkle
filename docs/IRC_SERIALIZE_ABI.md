# IRC outbound message serializer ABI

`irc_send_context_message(fd, operation, target, target_len, text, text_len, scratch, capacity)` serialises and sends one IRC frame through `irc_tcp_send_all`. Operations are 1 PRIVMSG, 2 ACTION and 3 TOPIC. The serializer emits `PRIVMSG target :text\r\n`, CTCP-wrapped `PRIVMSG target :\x01ACTION text\x01\r\n`, or `TOPIC target :text\r\n` respectively.

The caller supplies scratch storage; capacity is checked before any output bytes are written. Target and text are explicit-length byte strings. NUL, CR and LF are rejected in both; ASCII space is also rejected in the target. Empty targets and unsupported operations are rejected. Text may be empty. Returns 0 after the complete frame is sent, or -1 for invalid/unsafe input or transport failure. No user-provided string is interpreted as a format string.
