#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern int bot_strip_address_prefix(const char *, size_t, const char *, size_t,
                                    size_t *, size_t *);

struct bot_context_result { size_t start; uint32_t len; uint32_t addressed; };
extern struct bot_context_result bot_context_prepare_privmsg(
    const char *, size_t, const char *, size_t, const char *, size_t);

static void check(const char *text, const char *nick, int expected,
                  const char *remainder) {
    size_t start=99, len=99;
    int got=bot_strip_address_prefix(text, strlen(text), nick, strlen(nick),
                                     &start, &len);
    assert(got == expected);
    if (expected) {
        assert(start <= strlen(text));
        assert(len <= strlen(text)-start);
        assert(len == strlen(remainder));
        assert(memcmp(text+start,remainder,len)==0);
    } else {
        assert(start==0 && len==0);
    }
}
int main(void) {
    check("Bot: hello there", "bot", 1, "hello there");
    check("bOt,  hello  ", "BOT", 1, "hello");
    check("Bot>hello", "bot", 1, "hello");
    check("Bot-hello", "bot", 1, "hello");
    check("Bot;hello", "bot", 1, "hello");
    check("Bot hello", "bot", 0, NULL);
    check("Bot", "bot", 0, NULL);
    check("Other: hello", "bot", 0, NULL);
    check("Bot:", "bot", 1, "");
    const char *prefixed = "  Bot: hello  ";
    struct bot_context_result result = bot_context_prepare_privmsg(
        prefixed, strlen(prefixed), "Bot", 3, "#chan", 5);
    assert(result.start == 7 && result.len == 5 && result.addressed == 1);
    assert(memcmp(prefixed + result.start, "hello", result.len) == 0);

    const char *plain = "  hello  ";
    result = bot_context_prepare_privmsg(plain, strlen(plain),
                                         "Bot", 3, "Bot", 3);
    assert(result.start == 2 && result.len == 5 && result.addressed == 1);
    result = bot_context_prepare_privmsg(plain, strlen(plain),
                                         "Bot", 3, "bot", 3);
    assert(result.addressed == 0); /* target equality follows exact Go compare */
    result = bot_context_prepare_privmsg(plain, strlen(plain),
                                         "Bot", 3, "#chan", 5);
    assert(result.start == 2 && result.len == 5 && result.addressed == 0);
    puts("context tests: PASS");
    return 0;
}
