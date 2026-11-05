#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct irc_message {
    uint32_t tags_offset, tags_length;
    uint32_t prefix_offset, prefix_length;
    uint32_t command_offset, command_length;
    uint32_t param_count, flags;
    struct { uint32_t offset, length; } params[15];
};
struct bot_privmsg_views {
    const char *nick; uint64_t nick_len;
    const char *target; uint64_t target_len;
    const char *text; uint64_t text_len;
};
extern int bot_irc_privmsg_views(const char *, size_t,
                                 const struct irc_message *,
                                 struct bot_privmsg_views *);

int main(void) {
    const char line[] = ":Alice!u@host PRIVMSG #room :Bot: hello";
    struct irc_message m = {0};
    struct bot_privmsg_views v = {0};
    m.prefix_offset = 1; m.prefix_length = 12;
    m.command_offset = 14; m.command_length = 7;
    m.param_count = 2;
    m.params[0].offset = 22; m.params[0].length = 5;
    m.params[1].offset = 29; m.params[1].length = 10;
    assert(bot_irc_privmsg_views(line, strlen(line), &m, &v) == 1);
    assert(v.nick_len == 5 && memcmp(v.nick, "Alice", 5) == 0);
    assert(v.target_len == 5 && memcmp(v.target, "#room", 5) == 0);
    assert(v.text_len == 10 && memcmp(v.text, "Bot: hello", 10) == 0);

    m.command_length = 4;
    assert(bot_irc_privmsg_views(line, strlen(line), &m, &v) == 0);
    m.command_length = 7;
    m.params[1].offset = 1000;
    assert(bot_irc_privmsg_views(line, strlen(line), &m, &v) == -1);
    puts("IRC Context adapter tests: PASS");
    return 0;
}
