# Runtime ABI contracts

Target: x86-64 Linux, System V AMD64 ABI, NASM ELF64.

All public routines use the System V AMD64 calling convention. Integer and
pointer arguments are passed in RDI, RSI, RDX, RCX, R8 and R9; scalar results
are returned in RAX/EAX. RAX, RCX, RDX, RSI, RDI and R8-R11 are caller-saved.
Callee-saved registers (RBX, RBP, R12-R15) must be preserved. The direction
flag must be clear on entry and return.

## Strings

| Symbol | Arguments | Result | Contract |
|---|---|---|---|
| `str_len` | RDI = NUL-terminated string | RAX = byte length | Reads through the first NUL. |
| `strn_len` | RDI = byte pointer, RSI = maximum bytes | RAX = length | Reads no more than RSI bytes; returns RSI if no NUL occurs in range. |
| `str_ascii_casecmp` | RDI, RSI = NUL-terminated strings | EAX = -1, 0 or 1 | ASCII-only case-insensitive comparison. |
| `str_ascii_casecmp_n` | RDI, RSI = byte pointers, RDX = maximum bytes | EAX = -1, 0 or 1 | Compares at most RDX bytes; stops early if equal NUL bytes are encountered. |

Comparison results are sign-only and are not promised to equal the arithmetic
difference between the first differing bytes. Bytes outside ASCII A-Z are
compared unchanged. These functions are byte-oriented, not Unicode-aware.

## Memory

| Symbol | Arguments | Result | Contract |
|---|---|---|---|
| `mem_copy` | RDI = destination, RSI = source, RDX = byte count | RAX = original destination | Copies exactly RDX bytes. Ranges must not overlap (memcpy semantics). |
| `mem_equal` | RDI, RSI = byte pointers, RDX = byte count | EAX = -1, 0 or 1 | Zero means all bytes match; otherwise sign indicates unsigned-byte ordering at the first difference. |

A zero byte count is valid and causes no memory access. The caller is
responsible for ensuring that every non-empty range is readable/writable as
required and remains valid for the duration of the call.

## IRC byte buffers

Network input must always be represented as pointer plus explicit length.
NUL-terminated helpers are only for strings that have already been copied into
a bounded, terminated buffer. Do not pass untrusted socket buffers to
`str_len` or `strcmp`.

## IRC message parser

`irc_parse_message(buf, len, out)` takes RDI=buffer, RSI=byte length and
RDX=output structure. It returns 0 on success and -1 for malformed input.
The output occupies 152 bytes and contains uint32 offsets/lengths into the
original input buffer:

| Byte offset | Field |
|---:|---|
| 0, 4 | tags offset, tags length |
| 8, 12 | prefix offset, prefix length |
| 16, 20 | command offset, command length |
| 24 | parameter count |
| 28 | flags (bit 0 means the final parameter was introduced by a colon) |
| 32 | 15 pairs of parameter offset and length (8 bytes per pair) |

Absent tags/prefix are represented by zero offset and length. Parameter
offsets and lengths exclude the separating spaces and, for a trailing
parameter, exclude its leading colon. The trailing parameter consumes the
rest of the frame and may be empty. The parser accepts alphabetic commands
or exactly three decimal digits, and up to 15 parameters. It rejects empty
frames, NUL/CR/LF bytes, empty tags/prefixes/commands and malformed commands.
The input frame excludes CRLF; callers must strip the IRC line terminator
before parsing. The parser does not allocate or copy input data.
\n## IRC TCP transport\n\n| Symbol | Arguments | Result | Contract |\n|---|---|---|---|\n| `irc_tcp_connect` | RDI = NUL-terminated host, RSI = NUL-terminated decimal service | RAX = connected fd or -1 | Resolves with `getaddrinfo(AF_UNSPEC, SOCK_STREAM)`, tries returned addresses in order, and returns a blocking TCP socket. Caller owns the fd. |\n| `irc_tcp_send_all` | EDI = fd, RSI = byte pointer, RDX = length | EAX = 0 or -1 | Sends all bytes using `send(MSG_NOSIGNAL)`; zero-length sends succeed. A syscall error, including interruption, returns -1. |\n| `irc_tcp_recv_line` | EDI = fd, RSI = writable buffer, RDX = capacity | RAX = length, 0 on clean EOF, -1 on error | Reads until LF, strips one preceding CR, and appends NUL. Capacity includes the NUL. EOF after a partial line is an error. First implementation reads one byte per `recv`. |\n\nTransport routines are blocking and do not implement TLS, registration, reconnect/backoff, socket timeouts or multi-server lifecycle. The caller must append CRLF when sending IRC protocol lines and pass the returned line length to `irc_parse_message`.\n