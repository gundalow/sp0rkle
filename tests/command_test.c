#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>

struct bot_command_entry {
    const char *prefix;
    uint64_t prefix_len;
    void *handler;
    const char *help;
};

extern ssize_t bot_command_possible(const struct bot_command_entry *, uint32_t,
                                    const char *, size_t, const char **, size_t);

extern const char *bot_command_help_text(const struct bot_command_entry *, uint32_t,
                                       const char *, size_t);

extern int bot_is_factoid_addition(const char *, size_t);

extern int bot_command_dispatch(const struct bot_command_entry *, uint32_t,
                                const char *, size_t, int,
                                int,
                                char *, size_t, void **);

struct bot_line_filter {
    int (*should_process)(void *, const char *, size_t);
    void *ctx;
};
struct bot_command_request {
    const struct bot_line_filter *filters;
    uint32_t filter_count;
    const char *nick;
    size_t nick_len;
    const struct bot_command_entry *entries;
    uint32_t command_count;
    const char *text;
    size_t text_len;
    uint32_t addressed;
    uint32_t factoid_addition;
    char *out_args;
    size_t out_capacity;
    void **out_handler;
};
extern int bot_command_process(const struct bot_command_request *);

static int reject_line(void *ctx, const char *nick, size_t len) {
    (void)ctx; (void)nick; (void)len;
    return 0;
}

extern ssize_t bot_command_normalize_args(const char *, size_t, char *, size_t);

extern const struct bot_command_entry *bot_command_match(
    const struct bot_command_entry *, uint32_t, const char *, size_t, size_t *);

int main(void) {
    struct bot_command_entry entries[] = {
        {"help", 4, (void *)1, "help text"},
        {"remind", 6, (void *)2, "remind help"},
        {"remind list", 11, (void *)3, "list help"},
        {"quote", 5, (void *)4, "quote help"},
        {"quote #", 7, (void *)5, "quote number help"},
    };
    size_t n = 999;
    const struct bot_command_entry *e;

    e = bot_command_match(entries, 5, "REMIND me", 9, &n);
    assert(e == &entries[1] && n == 6);
    e = bot_command_match(entries, 5, "Remind List 1", 13, &n);
    assert(e == &entries[2] && n == 11);
    e = bot_command_match(entries, 5, "QUOTE #12", 9, &n);
    assert(e == &entries[4] && n == 7);
    e = bot_command_match(entries, 5, "help me", 7, &n);
    assert(e == &entries[0] && n == 4);
    e = bot_command_match(entries, 5, "unknown", 7, &n);
    assert(e == NULL && n == 0);
    e = bot_command_match(entries, 5, "rem", 3, &n);
    assert(e == NULL && n == 0);
    char normalized[32];
    ssize_t out_len;
    out_len = bot_command_normalize_args("  one   two\t three  ", strlen("  one   two\t three  "),
                                         normalized, sizeof(normalized));
    assert(out_len == 13);
    assert(strcmp(normalized, "one two three") == 0);
    out_len = bot_command_normalize_args(" \t\r\n ", 5,
                                         normalized, sizeof(normalized));
    assert(out_len == 0 && normalized[0] == 0);
    out_len = bot_command_normalize_args("hello", 5, normalized, 5);
    assert(out_len == -1 && normalized[0] == 0);
    assert(bot_command_help_text(entries, 5, "Remind List 1", 13) == entries[2].help);
    assert(bot_command_help_text(entries, 5, "unknown", 7) == NULL);
    const char *possible[10];
    ssize_t possible_count = bot_command_possible(entries, 5, "list", 4,
                                                   possible, 10);
    assert(possible_count == 1 && possible[0] == entries[2].prefix);
    possible_count = bot_command_possible(entries, 5, "quo", 3, possible, 10);
    assert(possible_count == 2 && possible[0] == entries[3].prefix &&
           possible[1] == entries[4].prefix);
    possible_count = bot_command_possible(entries, 5, "zz", 2, possible, 10);
    assert(possible_count == 0);
    possible_count = bot_command_possible(entries, 5, "list", 4, possible, 0);
    assert(possible_count == 0);
    assert(bot_is_factoid_addition("fact:is true", 12) == 1);
    assert(bot_is_factoid_addition("FACT:IS value", 13) == 1);
    assert(bot_is_factoid_addition("key:=value", 10) == 1);
    assert(bot_is_factoid_addition("ordinary message", 16) == 0);
    assert(bot_is_factoid_addition("fact: is true", 13) == 0);
    assert(bot_is_factoid_addition(":i", 2) == 0);
    assert(bot_is_factoid_addition(":=", 2) == 1);
    void *handler = NULL;
    int dispatched = bot_command_dispatch(entries, 5, "Remind List  1", strlen("Remind List  1"),
                                           1, 0, normalized,
                                           sizeof(normalized), &handler);
    assert(dispatched == 1 && handler == (void *)3);
    assert(strcmp(normalized, "1") == 0);
    handler = (void *)99;
    dispatched = bot_command_dispatch(entries, 5, "help", 4, 0, 0,
                                       normalized, sizeof(normalized), &handler);
    assert(dispatched == 0 && handler == NULL);
    dispatched = bot_command_dispatch(entries, 5, "learn something", 15, 1,
                                       1, normalized,
                                       sizeof(normalized), &handler);
    assert(dispatched == 0 && handler == NULL);
    dispatched = bot_command_dispatch(entries, 5, "not-a-command", 13, 1,
                                       0, normalized, sizeof(normalized),
                                       &handler);
    assert(dispatched == 0 && handler == NULL);
    struct bot_command_request request = {
        .filters = NULL, .filter_count = 0,
        .nick = "normal", .nick_len = 6,
        .entries = entries, .command_count = 5,
        .text = "help", .text_len = 4,
        .addressed = 1, .factoid_addition = 0,
        .out_args = normalized, .out_capacity = sizeof(normalized),
        .out_handler = &handler
    };
    handler = NULL;
    assert(bot_command_process(&request) == 1);
    assert(handler == (void *)1);

    struct bot_line_filter reject_filter = { reject_line, NULL };
    request.filters = &reject_filter;
    request.filter_count = 1;
    handler = (void *)99;
    strcpy(normalized, "stale");
    assert(bot_command_process(&request) == 0);
    assert(handler == NULL && normalized[0] == 0);
    puts("command tests: PASS");
    return 0;
}
