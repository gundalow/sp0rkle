#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct result { uint64_t offset; uint32_t length; int32_t delta; };
extern long karma_parse_annotations(const char *, size_t, struct result *, size_t);
static void expect(const char *s, const struct result *want, size_t n) {
    struct result got[16] = {{0}};
    long count = karma_parse_annotations(s, strlen(s), got, 16);
    assert(count == (long)n);
    for (size_t i = 0; i < n; ++i) {
        assert(got[i].offset == want[i].offset);
        assert(got[i].length == want[i].length);
        assert(got[i].delta == want[i].delta);
        assert(got[i].offset + got[i].length <= strlen(s));
    }
}
int main(void) {
    const char *s1 = "a++ b-- c++";
    const struct result w1[] = {{8,1,1},{4,1,-1},{0,1,1}};
    expect(s1, w1, 3);
    const char *s2 = " (a b c)-- d++ ";
    const struct result w2[] = {{11,1,1},{2,5,-1}};
    expect(s2, w2, 2);
    const char *s3 = "some funky karma-- text";
    const struct result w3[] = {{11,5,-1}};
    expect(s3, w3, 1);
    expect("no karma here", NULL, 0);
    expect("a b c)++", NULL, 0);
    expect("foo -- bar", NULL, 0);
    expect("++.++++++", NULL, 0);
    expect("http://foo.bar/some-url--with-hyphens", NULL, 0);
    struct result out[1];
    assert(karma_parse_annotations("a++ b++", 7, out, 1) == -1);
    puts("Karma parser tests: PASS");
    return 0;
}
