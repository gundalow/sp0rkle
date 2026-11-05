# Karma annotation application ABI

`karma_apply_annotations(request)` connects parser spans to caller-provided storage callbacks. The 104-byte request contains text, annotation array/count, voter/time, lookup and put callbacks, callback context, key scratch buffer/capacity, and an 88-byte record scratch area.

Lookup ABI: `int lookup(ctx, key, key_len, record_out)` returns 1 found, 0 absent, negative error. Put ABI: `int put(ctx, record)` returns 0 success, negative error. New records preserve the first subject spelling and use the ASCII-normalised key. Annotations are applied in parser order. Failure stops processing but does not roll back earlier successful puts. Callbacks must copy retained data because pointers may refer to caller scratch/input buffers. Durable keyed storage remains outstanding.
