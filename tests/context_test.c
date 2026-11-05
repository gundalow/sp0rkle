#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

extern int bot_strip_address_prefix(const char *, size_t, const char *, size_t,
                                    size_t *, size_t *);

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
    puts("context tests: PASS");
    return 0;
}
