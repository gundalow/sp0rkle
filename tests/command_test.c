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

extern int bot_command_dispatch(const struct bot_command_entry *, uint32_t,
                                const char *, size_t, int,
                                int,
                                char *, size_t, void **);

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
    puts("command tests: PASS");
    return 0;
}
