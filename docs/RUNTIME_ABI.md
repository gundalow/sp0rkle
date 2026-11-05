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
