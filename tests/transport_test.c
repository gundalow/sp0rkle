#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

struct irc_param {
    uint32_t offset;
    uint32_t length;
};

struct irc_message {
    uint32_t tags_offset, tags_length;
    uint32_t prefix_offset, prefix_length;
    uint32_t command_offset, command_length;
    uint32_t param_count, flags;
    struct irc_param params[15];
};

extern int irc_send_registration(int fd, const char *nick,
                                 const char *user, const char *realname);
extern int irc_session_next(int fd, char *line, size_t capacity,
                            struct irc_message *out);
extern int irc_session_wait_welcome(int fd, char *line, size_t capacity,
                                    struct irc_message *out);
extern int irc_send_join(int fd, const char *channel);

static void fail(const char *message) {
    fprintf(stderr, "transport test: %s\n", message);
    exit(1);
}

static void read_exact(int fd, char *buf, size_t length) {
    size_t done = 0;
    while (done < length) {
        ssize_t n = read(fd, buf + done, length - done);
        if (n <= 0) fail("unexpected EOF while reading peer data");
        done += (size_t)n;
    }
}

static void test_registration(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0)
        fail("socketpair for registration failed");

    if (irc_send_registration(sv[0], "bot", "botuser", "Bot Realname") != 0)
        fail("irc_send_registration returned an error");

    const char expected[] =
        "NICK bot\r\n"
        "USER botuser 0 * :Bot Realname\r\n";
    char actual[sizeof(expected)];
    read_exact(sv[1], actual, sizeof(expected) - 1);
    if (memcmp(actual, expected, sizeof(expected) - 1) != 0)
        fail("registration wire format did not match");

    close(sv[0]);
    close(sv[1]);
}

static void test_join(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0)
        fail("socketpair for JOIN failed");
    if (irc_send_join(sv[0], "#test") != 0)
        fail("irc_send_join returned an error");

    const char expected[] = "JOIN #test\\r\\n";
    char actual[sizeof(expected)];
    read_exact(sv[1], actual, sizeof(expected) - 1);
    if (memcmp(actual, expected, sizeof(expected) - 1) != 0)
        fail("JOIN wire format did not match");
    close(sv[0]);
    close(sv[1]);
}

static void test_welcome_and_nick_in_use(void) {
    int sv[2];
    char line[512];
    struct irc_message message;

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0)
        fail("socketpair for welcome failed");
    const char welcome[] = ":server 001 bot :Welcome\\r\\n";
    if (write(sv[1], welcome, sizeof(welcome) - 1) !=
        (ssize_t)(sizeof(welcome) - 1))
        fail("could not write welcome frame");
    if (irc_session_wait_welcome(sv[0], line, sizeof(line), &message) != 1)
        fail("welcome numeric was not detected");
    if (message.command_length != 3 || strcmp(line, ":server 001 bot :Welcome") != 0)
        fail("welcome event fields were incorrect");
    close(sv[0]);
    close(sv[1]);

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0)
        fail("socketpair for nick-in-use failed");
    const char nick_error[] = ":server 433 * bot :Nickname in use\\r\\n";
    if (write(sv[1], nick_error, sizeof(nick_error) - 1) !=
        (ssize_t)(sizeof(nick_error) - 1))
        fail("could not write nick-in-use frame");
    if (irc_session_wait_welcome(sv[0], line, sizeof(line), &message) != -2)
        fail("numeric 433 was not reported");
    close(sv[0]);
    close(sv[1]);
}

static void test_ping_pong_and_event(void) {
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0)
        fail("socketpair for session failed");

    const char input[] = "PING :token123\r\nPRIVMSG #chan :hello world\r\n";
    if (write(sv[1], input, sizeof(input) - 1) != (ssize_t)(sizeof(input) - 1))
        fail("could not write test IRC frames");

    char line[512];
    struct irc_message message;
    int result = irc_session_next(sv[0], line, sizeof(line), &message);
    if (result != 1) fail("session did not return the non-PING event");
    if (strcmp(line, "PRIVMSG #chan :hello world") != 0)
        fail("session returned unexpected IRC line");
    if (message.command_length != 7 || message.param_count != 2)
        fail("parsed event fields were incorrect");

    const char expected[] = "PONG :token123\r\n";
    char actual[sizeof(expected)];
    read_exact(sv[1], actual, sizeof(expected) - 1);
    if (memcmp(actual, expected, sizeof(expected) - 1) != 0)
        fail("PING did not produce the expected PONG");

    close(sv[0]);
    close(sv[1]);
}

int main(void) {
    test_registration();
    test_join();
    test_welcome_and_nick_in_use();
    test_ping_pong_and_event();
    puts("transport tests: PASS");
    return 0;
}
