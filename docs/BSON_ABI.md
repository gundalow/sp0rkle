# BSON ABI

## Structural validator

`bson_document_validate(document, document_len)` validates a BSON document without allocating memory. It checks the declared document size, final terminator, element-name C strings, value bounds and supported BSON element layouts. Embedded documents, arrays and code-with-scope documents are recursively validated with a maximum nesting depth of 32.

Recognised BSON types include double, string, document, array, binary, undefined, ObjectId, boolean, datetime, null, regex, DBPointer, JavaScript code, symbol, code-with-scope, int32, timestamp, int64, Decimal128, MaxKey and MinKey. Boolean values are restricted to 0 or 1. Length-bearing values are checked against the enclosing document boundary.

The validator does not enforce UTF-8 validity, canonical array index names, duplicate field-name policy, or all semantic restrictions of every BSON subtype. It is a structural safety layer, not a complete semantic BSON implementation.

## Karma schema codec

`karma_bson_encode` and `karma_bson_decode` provide the current schema-specific record codec. See `docs/KARMA_STORE_ABI.md` for its record field order, Go-compatible integer-width selection, zero-time encoding and caller-owned buffer requirements.

A general descriptor-driven BSON encoder/decoder and codecs for the remaining collections are still outstanding.