#include <assert.h>
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>

struct bot_rewriter {
    ssize_t (*rewrite)(void *, const char *, size_t, char *, size_t);
    void *ctx;
};
extern const char *bot_rewrite_apply(const struct bot_rewriter *, uint32_t,
                                     const char *, size_t, char *, char *,
                                     size_t, size_t *);

static ssize_t uppercase(void *ctx, const char *in, size_t len,
                         char *out, size_t cap) {
    (void)ctx;
    if (len >= cap) return -1;
    for (size_t i = 0; i < len; ++i)
        out[i] = (char)toupper((unsigned char)in[i]);
    return (ssize_t)len;
}

static ssize_t suffix(void *ctx, const char *in, size_t len,
                      char *out, size_t cap) {
    const char *s = ctx;
    size_t n = strlen(s);
    if (len + n >= cap) return -1;
    memcpy(out, in, len);
    memcpy(out + len, s, n);
    return (ssize_t)(len + n);
}

static ssize_t fail(void *ctx, const char *in, size_t len,
                    char *out, size_t cap) {
    (void)ctx; (void)in; (void)len; (void)out; (void)cap;
    return -1;
}

int main(void) {
    char a[64], b[64];
    size_t len = 99;
    const char *input = "hello";

    const char *result = bot_rewrite_apply(NULL, 0, input, 5,
                                           a, b, sizeof(a), &len);
    assert(result == input && len == 5);

    struct bot_rewriter chain[] = {
        { uppercase, NULL },
        { suffix, "!" },
        { NULL, NULL }
    };
    result = bot_rewrite_apply(chain, 3, input, 5,
                               a, b, sizeof(a), &len);
    assert(result != NULL && len == 6);
    assert(memcmp(result, "HELLO!", 6) == 0 && result[6] == 0);

    struct bot_rewriter too_long[] = { { suffix, "a very long suffix" } };
    result = bot_rewrite_apply(too_long, 1, input, 5,
                               a, b, 8, &len);
    assert(result == NULL);

    struct bot_rewriter failure[] = { { fail, NULL } };
    result = bot_rewrite_apply(failure, 1, input, 5,
                               a, b, sizeof(a), &len);
    assert(result == NULL);

    puts("rewrite tests: PASS");
    return 0;
}
