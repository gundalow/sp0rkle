#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct irc_message {
    uint32_t tags_offset, tags_length;
    uint32_t prefix_offset, prefix_length;
    uint32_t command_offset, command_length;
    uint32_t param_count, flags;
    struct { uint32_t offset, length; } params[15];
};
typedef int (*filter_fn)(void *, const char *, size_t);
struct bot_line_filter { filter_fn should_process; void *ctx; };
struct command_entry {
    const char *prefix;
    uint64_t prefix_len;
    void *handler;
    const char *help;
};
struct bot_irc_command_request {
    const char *line;
    size_t line_len;
    const struct irc_message *message;
    const char *botnick;
    size_t botnick_len;
    const struct bot_line_filter *filters;
    uint32_t filter_count;
    const struct command_entry *commands;
    uint32_t command_count;
    char *out_args;
    size_t out_capacity;
    void **out_handler;
};
struct bot_privmsg_context {
    const char *nick; uint64_t nick_len;
    const char *target; uint64_t target_len;
    const char *body; uint64_t body_len;
    const char *reply_target; uint64_t reply_target_len;
    uint32_t addressed, reserved;
};
extern int bot_irc_privmsg_command_process(
    const struct bot_irc_command_request *);
extern int bot_irc_privmsg_execute(
    const struct bot_irc_command_request *, void *);

static int handler_calls;
static int command_handler(void *opaque,
                           const struct bot_privmsg_context *ctx,
                           const char *args, size_t args_len) {
    (void)opaque;
    assert(ctx->addressed == 1);
    assert(ctx->nick_len == 5 && memcmp(ctx->nick, "Alice", 5) == 0);
    assert(ctx->reply_target_len == 5 &&
           memcmp(ctx->reply_target, "#room", 5) == 0);
    assert(args_len == 5 && memcmp(args, "hello", 5) == 0);
    ++handler_calls;
    return 73;
}

static int allow(void *ctx, const char *nick, size_t len) {
    (void)ctx; (void)nick; (void)len;
    return 1;
}
static int reject(void *ctx, const char *nick, size_t len) {
    (void)ctx; (void)nick; (void)len;
    return 0;
}
static void setup_message(struct irc_message *m) {
    memset(m, 0, sizeof(*m));
    m->prefix_offset = 1; m->prefix_length = 12;
    m->command_offset = 14; m->command_length = 7;
    m->param_count = 2;
    m->params[0].offset = 22; m->params[0].length = 5;
    m->params[1].offset = 29; m->params[1].length = 15;
}
int main(void) {
    const char line[] = ":Alice!u@host PRIVMSG #room :Bot: ping hello";
    struct irc_message message;
    setup_message(&message);
    struct bot_line_filter filter = { allow, NULL };
    struct command_entry command = { "ping", 4, (void *)command_handler, "ping help" };
    char args[32] = {0};
    void *handler = NULL;
    struct bot_irc_command_request request = {
        line, sizeof(line) - 1, &message, "Bot", 3,
        &filter, 1, &command, 1, args, sizeof(args), &handler
    };

    assert(bot_irc_privmsg_command_process(&request) == 1);
    assert(strcmp(args, "hello") == 0);
    assert(handler == (void *)command_handler);
    assert(bot_irc_privmsg_execute(&request, NULL) == 73);
    assert(handler_calls == 1);

    filter.should_process = reject;
    strcpy(args, "stale");
    handler = (void *)0x5678;
    assert(bot_irc_privmsg_command_process(&request) == 0);
    assert(args[0] == 0 && handler == NULL);

    filter.should_process = allow;
    const char factoid[] = ":Alice!u@host PRIVMSG #room :Bot: thing := value";
    struct irc_message factoid_message;
    setup_message(&factoid_message);
    factoid_message.params[1].length = sizeof("Bot: thing := value") - 1;
    request.line = factoid;
    request.line_len = sizeof(factoid) - 1;
    request.message = &factoid_message;
    assert(bot_irc_privmsg_command_process(&request) == 0);
    assert(handler == NULL && args[0] == 0);

    puts("IRC command integration tests: PASS");
    return 0;
}
