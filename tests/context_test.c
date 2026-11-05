#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

extern int bot_strip_address_prefix(const char *, size_t, const char *, size_t,
                                    size_t *, size_t *);

extern int bot_context_prepare_privmsg(const char *, size_t,
                                      const char *, size_t,
                                      const char *, size_t,
                                      size_t *, size_t *, int *);

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
    size_t start, len;
    int addressed;
    const char *prefixed = "  Bot: hello  ";
    assert(bot_context_prepare_privmsg(prefixed, strlen(prefixed),
                                       "Bot", 3, "#chan", 5,
                                       &start, &len, &addressed) == 0);
    fprintf(stderr, "prepared start=%zu len=%zu addressed=%d\n", start, len, addressed);
    assert(start == 7 && len == 5 && addressed == 1);
    assert(memcmp(prefixed + start, "hello", len) == 0);

    const char *plain = "  hello  ";
    assert(bot_context_prepare_privmsg(plain, strlen(plain),
                                       "Bot", 3, "Bot", 3,
                                       &start, &len, &addressed) == 0);
    assert(start == 2 && len == 5 && addressed == 1);
    assert(bot_context_prepare_privmsg(plain, strlen(plain),
                                       "Bot", 3, "bot", 3,
                                       &start, &len, &addressed) == 0);
    assert(addressed == 0); /* target equality follows the Go exact compare */
    assert(bot_context_prepare_privmsg(plain, strlen(plain),
                                       "Bot", 3, "#chan", 5,
                                       &start, &len, &addressed) == 0);
    assert(start == 2 && len == 5 && addressed == 0);
    puts("context tests: PASS");
    return 0;
}
