#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct annotation { uint64_t offset; uint32_t length; int32_t delta; };
struct karma_record {
    const char *subject; uint64_t subject_len; const char *key;
    int64_t score; uint64_t votes;
    const char *upvoter; uint64_t upvoter_len; int64_t upvtime;
    const char *downvoter; uint64_t downvoter_len; int64_t downvtime;
};
struct request {
    const char *text; uint64_t text_len;
    const struct annotation *items; uint64_t count;
    const char *voter; uint64_t voter_len; int64_t timestamp;
    int (*lookup)(void *, const char *, size_t, struct karma_record *);
    int (*put)(void *, const struct karma_record *);
    void *ctx; char *key; uint64_t key_capacity;
    struct karma_record *record;
};
extern long karma_parse_annotations(const char *, size_t, struct annotation *, size_t);
extern long karma_apply_annotations(const struct request *);
static struct karma_record stored;
static int have_record;
static int lookup(void *ctx, const char *key, size_t len, struct karma_record *out) {
    (void)ctx;
    if (!have_record || stored.key == NULL || strlen(stored.key) != len ||
        memcmp(stored.key, key, len) != 0) return 0;
    *out = stored;
    return 1;
}
static int put(void *ctx, const struct karma_record *r) {
    (void)ctx;
    stored = *r;
    have_record = 1;
    return 0;
}
int main(void) {
    const char text[] = "karma++ karma--";
    struct annotation items[4];
    assert(karma_parse_annotations(text, sizeof(text)-1, items, 4) == 2);
    char key[32];
    struct karma_record scratch;
    struct request req = {
        text, sizeof(text)-1, items, 2, "Alice", 5, 1234,
        lookup, put, NULL, key, sizeof(key), &scratch
    };
    assert(karma_apply_annotations(&req) == 2);
    assert(have_record);
    assert(stored.score == 0 && stored.votes == 2);
    assert(stored.subject_len == 5 && memcmp(stored.subject, "karma", 5) == 0);
    assert(stored.key && strcmp(stored.key, "karma") == 0);
    assert(stored.upvoter_len == 5 && stored.upvtime == 1234);
    assert(stored.downvoter_len == 5 && stored.downvtime == 1234);
    puts("Karma annotation application tests: PASS");
    return 0;
}
