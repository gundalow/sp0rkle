#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
extern int irc_send_context_message(int, int, const char *, size_t,
                                    const char *, size_t, char *, size_t);
static void check(int fd, const char *expected) {
    char buf[256] = {0};
    size_t need = strlen(expected);
    ssize_t n = read(fd, buf, sizeof(buf));
    assert(n == (ssize_t)need);
    assert(memcmp(buf, expected, need) == 0);
}
int main(void) {
    int sv[2];
    char scratch[256];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0);
    assert(irc_send_context_message(sv[0], 1, "#room", 5, "hello", 5,
                                    scratch, sizeof(scratch)) == 0);
    check(sv[1], "PRIVMSG #room :hello\r\n");
    assert(irc_send_context_message(sv[0], 2, "#room", 5, "waves", 5,
                                    scratch, sizeof(scratch)) == 0);
    const char action[] = "PRIVMSG #room :\001ACTION waves\001\r\n";
    check(sv[1], action);
    assert(irc_send_context_message(sv[0], 3, "#room", 5, "topic", 5,
                                    scratch, sizeof(scratch)) == 0);
    check(sv[1], "TOPIC #room :topic\r\n");
    assert(irc_send_context_message(sv[0], 1, "#room", 5, "bad\r\nQUIT", 9,
                                    scratch, sizeof(scratch)) == -1);
    assert(irc_send_context_message(sv[0], 1, "#room", 5, "hello", 5,
                                    scratch, 4) == -1);
    close(sv[0]); close(sv[1]);
    puts("IRC serializer tests: PASS");
    return 0;
}
