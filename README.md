# sp0rkle (x86-64 NASM/Linux port)

This branch is the clean-room assembly implementation track. It targets Linux
x86-64, uses NASM syntax, and links against the system C library for POSIX
facilities. The behavioural contract is in [SPEC.md](SPEC.md).

## Build

Requirements: x86-64 Linux, NASM, GCC or a compatible C compiler, GNU Make.

```sh
make
make test
./build/sp0rkle --version
```

The current executable is an implementation scaffold, not yet an IRC bot. It
provides the native build, runtime conventions, and initial protocol/string
primitives on which the feature port will be built. It deliberately does not
claim support for persistence, IRC connections, or domain drivers yet.

## Development rules

* Keep domain behaviour aligned with `SPEC.md`; unresolved items remain
  explicit rather than being guessed.
* Use the System V AMD64 ABI at public function boundaries.
* NASM modules export documented symbols with `global` and import dependencies
  with `extern`.
* Caller-saved registers may be clobbered; preserve RBX, RBP, and R12-R15.
* Return scalar values in RAX. Pass pointers in RDI, RSI, RDX, RCX, R8, R9.
* Strings are NUL-terminated at C ABI boundaries. Protocol buffers must also
  carry explicit lengths; do not assume network data is NUL-terminated.
* Keep protocol/domain logic independently testable without a live IRC server.

## Current milestone

See [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) for the
implemented foundation and remaining specification work.
