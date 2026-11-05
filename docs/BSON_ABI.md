# BSON ABI

## Structural validator

`bson_document_validate(document, document_len)` validates a BSON document without allocating memory. It checks the declared document size, final terminator, element-name C strings, value bounds and supported BSON element layouts. Embedded documents, arrays and code-with-scope documents are recursively validated with a maximum nesting depth of 32.

Recognised BSON types include double, string, document, array, binary, undefined, ObjectId, boolean, datetime, null, regex, DBPointer, JavaScript code, symbol, code-with-scope, int32, timestamp, int64, Decimal128, MaxKey and MinKey. Boolean values are restricted to 0 or 1. Length-bearing values are checked against the enclosing document boundary.

The validator does not enforce UTF-8 validity, canonical array index names, duplicate field-name policy, or all semantic restrictions of every BSON subtype. It is a structural safety layer, not a complete semantic BSON implementation.

## Descriptor-driven document encoder

`bson_document_encode(fields, count, out, capacity, out_len)` writes a document from 40-byte field descriptors. Each descriptor contains a field-name pointer/length, a BSON type code, and a pointer/length to the raw BSON value bytes. It preflights all names and total capacity before modifying output, writes the document envelope and element headers, then runs the structural validator on the completed document.

The caller is responsible for supplying correctly encoded value bytes for the selected BSON type. If a raw value is malformed, the function returns -1 after writing the document; the output is then unspecified. Field names must not contain NUL bytes.

## Generic field lookup

`bson_find_field(doc, len, name, name_len, out)` first validates the complete document, then returns the first exact bytewise field-name match. Its 24-byte output contains the BSON type at offset 0, raw value pointer at offset 8 and raw value byte length at offset 16. It returns 1 when found, 0 when absent, or -1 for malformed input. The returned value pointer is a view into the caller's document buffer.

## Scalar value decoder

`bson_decode_scalar(type, raw_value, raw_len, out, capacity, out_len)` converts a field value returned by `bson_find_field`. It supports strings, int32-to-int64 widening, int64/datetime/timestamp, double bit copies, booleans, ObjectIds, Decimal128, binary payloads, nested documents/arrays and validated raw regex/DBPointer/code-with-scope values. String output is NUL-terminated; binary output omits the BSON length/subtype header; nested documents are copied whole. It returns -1 on type, bounds or capacity mismatch and does not change `out_len` on failure.

## Karma schema codec

`karma_bson_encode` and `karma_bson_decode` provide the current schema-specific record codec. See `docs/KARMA_STORE_ABI.md` for its record field order, Go-compatible integer-width selection, zero-time encoding and caller-owned buffer requirements.

A general-purpose BSON value decoder and codecs for the remaining collections are still outstanding.