#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

struct irc_message {
    uint32_t tags_offset, tags_length;
    uint32_t prefix_offset, prefix_length;
    uint32_t command_offset, command_length;
    uint32_t param_count, flags;
    struct { uint32_t offset, length; } params[15];
};

typedef void (*event_fn)(void *, const char *, size_t,
                         const struct irc_message *);
struct event_handler {
    const char *command;
    uint64_t command_length;
    event_fn callback;
    void *context;
};

extern int64_t irc_session_dispatch_next(int, char *, size_t, struct irc_message *, const struct event_handler *, uint64_t);
extern int64_t irc_event_dispatch(const struct event_handler *, uint64_t,
                                  const char *, uint64_t,
                                  const struct irc_message *);

struct state { int calls; int id; };
static void record(void *opaque, const char *line, size_t len,
                   const struct irc_message *message) {
    struct state *s = opaque;
    assert(line != NULL && len == strlen(line));
    assert(message->command_length == 7);
    s->calls = s->calls * 10 + s->id;
}

int main(void) {
    const char line[] = ":nick PRIVMSG #chan :hello";
    struct irc_message message = {0};
    message.prefix_offset = 1;
    message.prefix_length = 4;
    message.command_offset = 6;
    message.command_length = 7;
    struct state a = {0, 1}, b = {0, 2}, c = {0, 3};
    const struct event_handler handlers[] = {
        {"NOTICE", 6, record, &c},
        {"privmsg", 7, record, &a},
        {"PRIVMSG", 7, NULL, &c},
        {"PRIVMSG", 7, record, &b},
    };

    assert(irc_event_dispatch(handlers, 4, line, sizeof(line) - 1,
                              &message) == 2);
    assert(a.calls == 1);
    assert(b.calls == 2);
    assert(c.calls == 0);
    assert(irc_event_dispatch(handlers, 0, line, sizeof(line) - 1,
                              &message) == 0);
    message.command_offset = 99;
    assert(irc_event_dispatch(handlers, 4, line, sizeof(line) - 1,
                              &message) == -1);
    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    const char frame[] = ":nick PRIVMSG #chan :hello\r\n";
    assert(write(sockets[1], frame, sizeof(frame) - 1) == (ssize_t)(sizeof(frame) - 1));
    char input[512];
    memset(&message, 0, sizeof(message));
    assert(irc_session_dispatch_next(sockets[0], input, sizeof(input),
                                     &message, handlers, 4) == 2);
    assert(a.calls == 11);
    assert(b.calls == 22);
    close(sockets[0]);
    close(sockets[1]);
    puts("event dispatch tests: PASS");
    return 0;
}
