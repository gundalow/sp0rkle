#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct karma_record {
    const char *subject; uint64_t subject_len; const char *key;
    int64_t score; uint64_t votes;
    const char *upvoter; uint64_t upvoter_len; int64_t upvtime;
    const char *downvoter; uint64_t downvoter_len; int64_t downvtime;
};
extern long karma_key_normalize(const char *, size_t, char *, size_t);
extern int karma_record_apply(struct karma_record *, int, const char *, size_t, int64_t);
int main(void) {
    char key[32];
    assert(karma_key_normalize("Sp0rKle", 7, key, sizeof(key)) == 7);
    assert(strcmp(key, "sp0rkle") == 0);
    assert(karma_key_normalize("abc", 3, key, 3) == -1);
    struct karma_record r = {.subject="Sp0rKle",.subject_len=7,.key=key};
    assert(karma_record_apply(&r, 1, "Alice", 5, 1000) == 0);
    assert(r.score == 1 && r.votes == 1);
    assert(r.upvoter && r.upvoter_len == 5 && r.upvtime == 1000);
    assert(karma_record_apply(&r, -1, "Bob", 3, 2000) == 0);
    assert(r.score == 0 && r.votes == 2);
    assert(r.downvoter && r.downvoter_len == 3 && r.downvtime == 2000);
    r.score = INT64_MAX;
    assert(karma_record_apply(&r, 1, "A", 1, 3000) == -1);
    assert(r.score == INT64_MAX);
    r.score = INT64_MIN;
    assert(karma_record_apply(&r, -1, "A", 1, 3000) == -1);
    r.score = 0; r.votes = UINT64_MAX;
    assert(karma_record_apply(&r, 1, "A", 1, 3000) == -1);
    assert(r.votes == UINT64_MAX);
    puts("Karma record tests: PASS");
    return 0;
}
