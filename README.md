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
./build/sp0rkle --help
./build/sp0rkle -s irc.example.net -p 6667 -n sp0rklf -c '#channel'
```

The executable now provides a single-server plain-TCP IRC console client. It
registers a nickname, waits for the server welcome, joins one channel, answers
PING, and prints received IRC lines to stdout. It is not yet a full multi-server
bot and does not implement TLS, reconnects, or command handling.

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

The agreed delivery milestones are (1) an IRC console client and (2) the
`chance` command. Explicitly deferred features are listed in
[docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).
