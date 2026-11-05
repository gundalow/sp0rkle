#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef int (*filter_fn)(void *, const char *, size_t);
struct bot_line_filter { filter_fn should_process; void *ctx; };

extern int bot_nick_ignore_should_process(const char *, size_t,
                                          filter_fn, void *);
extern int bot_filter_pipeline_should_process(const struct bot_line_filter *,
                                               unsigned, const char *, size_t);

static int lookup(void *ctx, const char *nick, size_t len) {
    const char *blocked = (const char *)ctx;
    return strlen(blocked) == len && memcmp(blocked, nick, len) == 0;
}
static int allow_all(void *ctx, const char *nick, size_t len) {
    (void)ctx; (void)nick; (void)len;
    return 1;
}
static int reject_all(void *ctx, const char *nick, size_t len) {
    (void)ctx; (void)nick; (void)len;
    return 0;
}
static int count_call(void *ctx, const char *nick, size_t len) {
    int *calls = (int *)ctx;
    (void)nick; (void)len;
    ++*calls;
    return 1;
}

int main(void) {
    const char *blocked = "spammer";
    assert(bot_nick_ignore_should_process("SpAmMeR", 7, lookup,
                                          (void *)blocked) == 0);
    assert(bot_nick_ignore_should_process("Helpful", 7, lookup,
                                          (void *)blocked) == 1);
    assert(bot_nick_ignore_should_process("", 0, lookup,
                                          (void *)blocked) == 1);
    assert(bot_nick_ignore_should_process("Spammer", 7, NULL, NULL) == 1);

    struct bot_line_filter filters[2] = {
        { allow_all, NULL }, { reject_all, NULL }
    };
    assert(bot_filter_pipeline_should_process(filters, 2, "nick", 4) == 0);
    filters[1].should_process = allow_all;
    assert(bot_filter_pipeline_should_process(filters, 2, "nick", 4) == 1);
    int calls = 0;
    filters[0].should_process = count_call;
    filters[0].ctx = &calls;
    filters[1].should_process = reject_all;
    assert(bot_filter_pipeline_should_process(filters, 2, "nick", 4) == 0);
    assert(calls == 1); /* evaluated in order, short-circuits on rejection */
    assert(bot_filter_pipeline_should_process(NULL, 0, "nick", 4) == 1);

    puts("filter tests: PASS");
    return 0;
}
