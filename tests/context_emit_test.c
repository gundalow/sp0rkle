#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct emit_request {
    int (*send)(void *, uint32_t, const char *, size_t, const char *, size_t);
    void *send_ctx;
    uint32_t operation;
    const char *target;
    size_t target_len;
    const char *text;
    size_t text_len;
    const void *rewriters;
    uint32_t rewrite_count;
    char *scratch_a;
    char *scratch_b;
    size_t scratch_capacity;
    uint32_t apply_rewrites;
    uint32_t reserved[3];
};
extern int bot_context_emit(const struct emit_request *);
struct string_view { const char *ptr; size_t len; };
extern struct string_view bot_context_resolve_target(const char *, size_t, const char *, size_t);
extern size_t bot_context_prefix_nick(const char *, size_t, const char *, size_t,
                                      char *, size_t);

struct capture { uint32_t op; char target[32]; char text[128]; };
static int capture_send(void *opaque, uint32_t op, const char *target,
                        size_t target_len, const char *text, size_t text_len) {
    struct capture *c = opaque;
    assert(target_len < sizeof c->target && text_len < sizeof c->text);
    c->op = op;
    memcpy(c->target, target, target_len); c->target[target_len] = 0;
    memcpy(c->text, text, text_len); c->text[text_len] = 0;
    return 37;
}
static ssize_t upper(void *ctx, const char *in, size_t n, char *out, size_t cap) {
    (void)ctx;
    if (n >= cap) return -1;
    for (size_t i=0;i<n;i++) out[i]=(in[i]>='a'&&in[i]<='z')?in[i]-32:in[i];
    return (ssize_t)n;
}
int main(void) {
    struct string_view view = bot_context_resolve_target("#channel", 8, "alice", 5);
    assert(view.len == 8 && memcmp(view.ptr, "#channel", 8) == 0);
    view = bot_context_resolve_target("sp0rkle", 7, "alice", 5);
    assert(view.len == 5 && memcmp(view.ptr, "alice", 5) == 0);
    view = bot_context_resolve_target("&local", 6, "bob", 3);
    assert(view.len == 6 && memcmp(view.ptr, "&local", 6) == 0);
    struct capture c = {0};
    char a[128], b[128], prefixed[128];
    struct { void *fn; void *ctx; } rw = {(void *)upper, NULL};
    struct emit_request r = {
        .send=capture_send, .send_ctx=&c, .operation=1,
        .target="#chan", .target_len=5, .text="hello", .text_len=5,
        .rewriters=&rw, .rewrite_count=1, .scratch_a=a, .scratch_b=b,
        .scratch_capacity=sizeof a, .apply_rewrites=1
    };
    assert(bot_context_emit(&r)==37);
    assert(c.op==1 && strcmp(c.target,"#chan")==0 && strcmp(c.text,"HELLO")==0);

    r.operation=2; r.apply_rewrites=0;
    assert(bot_context_emit(&r)==37);
    assert(c.op==2 && strcmp(c.text,"hello")==0); /* explicit Action bypasses rewrites */

    size_t n=bot_context_prefix_nick("alice",5,"hello",5,prefixed,sizeof prefixed);
    assert(n==12 && strcmp(prefixed,"alice: hello")==0);
    assert(bot_context_prefix_nick("alice",5,"hello",5,prefixed,4)==(size_t)-1);

    r.send=NULL;
    assert(bot_context_emit(&r)==-1);
    puts("context emit tests: PASS");
    return 0;
}
