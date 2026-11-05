# IRC line filter ABI

## Nick ignore helper

`bot_nick_ignore_should_process(nick, nick_len, lookup, lookup_ctx)`

Returns 1 to process the line and 0 to suppress it. An empty nick always
passes. Otherwise it creates a temporary NUL-terminated ASCII-lowercase copy
of the nick and calls:

`int lookup(void *ctx, const char *lowercase_nick, size_t nick_len)`

The lookup callback returns nonzero when the ignore namespace has a non-empty
value for that key. This models the original Go filter, which lowercases the
nick before querying the namespace and suppresses on any non-empty value.
The input nick is not modified. Only ASCII case folding is performed.

## Filter pipeline

Each filter entry is 16 bytes:

- offset 0: callback pointer
- offset 8: callback context pointer

Callback signature:

`int should_process(void *ctx, const char *nick, size_t nick_len)`

`bot_filter_pipeline_should_process(filters, count, nick, nick_len)`
evaluates filters in registration order. All filters must return nonzero for
the line to pass. A null callback is skipped. Evaluation short-circuits at the
first callback returning zero. An empty pipeline allows the line.
