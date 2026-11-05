#include <assert.h>
#include <stdint.h>
#include <stdio.h>

struct poller_entry {
    void (*start)(void *);
    void (*stop)(void *);
    void (*poll)(void *, void *const *, size_t);
    void *ctx;
    uint32_t active;
    uint32_t reserved;
};
struct poller_state {
    uint64_t connection_count;
    struct poller_entry *entries;
    uint64_t entry_count;
};
extern void bot_poller_set_init(struct poller_state *, struct poller_entry *, size_t);
extern int bot_poller_set_add(struct poller_state *, size_t);
extern int bot_poller_set_connection(struct poller_state *, int);
extern int bot_poller_set_poll_all(struct poller_state *, void *const *, size_t);

struct counts { int starts, stops, polls; };
static void start(void *p) { ((struct counts *)p)->starts++; }
static void stop(void *p) { ((struct counts *)p)->stops++; }
static void poll(void *p, void *const *ctx, size_t n) {
    struct counts *c = p;
    assert(n == 2 && ctx[0] == (void *)1 && ctx[1] == (void *)2);
    c->polls++;
}
int main(void) {
    struct counts a = {0}, b = {0};
    struct poller_entry entries[2] = {
        {start, stop, poll, &a, 0, 0},
        {start, stop, poll, &b, 0, 0}
    };
    struct poller_state state;
    void *contexts[2] = {(void *)1, (void *)2};
    bot_poller_set_init(&state, entries, 2);
    assert(bot_poller_set_add(&state, 0) == 0);
    assert(bot_poller_set_connection(&state, 1) == 0);
    assert(a.starts == 1 && b.starts == 0);
    assert(bot_poller_set_connection(&state, 1) == 0);
    assert(a.starts == 1);
    assert(bot_poller_set_add(&state, 1) == 0);
    assert(b.starts == 1);
    assert(bot_poller_set_poll_all(&state, contexts, 2) == 2);
    assert(a.polls == 1 && b.polls == 1);
    assert(bot_poller_set_connection(&state, 0) == 0);
    assert(a.stops == 0 && b.stops == 0);
    assert(bot_poller_set_connection(&state, 0) == 0);
    assert(a.stops == 1 && b.stops == 1);
    assert(bot_poller_set_poll_all(&state, contexts, 2) == 0);
    assert(bot_poller_set_connection(&state, 0) == 0);
    puts("Poller lifecycle tests: PASS");
    return 0;
}
