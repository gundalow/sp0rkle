# IRC console client

The executable exposes a deliberately small single-server console mode:

```sh
./build/sp0rkle -s irc.example.net -p 6667 -n sp0rklf -c '#channel'
```

- `-s`: required IRC server hostname or address.
- `-p`: TCP service/port; defaults to `6667`.
- `-n`: nickname; defaults to `sp0rklf`.
- `-c`: required channel to join after numeric 001.
- `-h` / `--help`: print usage.
- `--version` and `--self-test` remain available.

Only one plain-TCP server and one channel are supported. TLS, server passwords,
multiple channels, reconnects, and background bot command dispatch are not part
of this milestone.

## Runtime sequence

1. `irc_console_run(host, service, nick, channel)` opens a TCP connection with
   `irc_tcp_connect`.
2. It sends NICK and USER using `irc_send_registration`.
3. It waits for numeric 001 with `irc_session_wait_welcome`; the welcome line
   is printed to stdout.
4. It sends JOIN for the configured channel.
5. It receives subsequent messages with `irc_session_next`. PING is answered
   with PONG by the session reader; each non-PING IRC line is printed to stdout.
6. Clean EOF closes the socket and returns 0. Connection, registration,
   nickname-in-use, join, or receive errors are printed to stdout and return -1.

The console uses a 512-byte line buffer and a 152-byte parsed-message buffer.
The transport/parser retain explicit lengths internally; the line reader adds a
NUL terminator for the shell output call.

## Test coverage

`tests/irc_console_test.c` starts a loopback TCP server on an ephemeral port,
launches the actual executable with its CLI arguments, verifies NICK/USER and
JOIN, sends welcome/PING/NOTICE frames, checks PONG, and asserts the received
welcome and NOTICE are printed. This exercises the executable entry point as
well as the transport sequence without an external IRC network.
