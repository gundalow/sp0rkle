#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct irc_message {
    uint32_t tags_offset, tags_length, prefix_offset, prefix_length;
    uint32_t command_offset, command_length, param_count, flags;
    struct { uint32_t offset, length; } params[15];
};
struct karma_record {
    const char *subject; uint64_t subject_len; const char *key;
    int64_t score; uint64_t votes;
    const char *upvoter; uint64_t upvoter_len; int64_t upvtime;
    const char *downvoter; uint64_t downvoter_len; int64_t downvtime;
};
struct karma_store_context {
    void *db;
    unsigned char *bson; uint64_t bson_capacity;
    unsigned char *encoded_key; uint64_t encoded_key_capacity;
    char *subject; uint64_t subject_capacity;
    char *key; uint64_t key_capacity;
    char *upvoter; uint64_t upvoter_capacity;
    char *downvoter; uint64_t downvoter_capacity;
};
struct karma_event_context {
    struct karma_store_context *store;
    struct { uint64_t offset; uint32_t length; int32_t delta; } *annotations;
    uint64_t annotation_capacity;
    char *key_scratch; uint64_t key_capacity;
    struct karma_record *record_scratch;
};
extern int db_store_open(const char *, void **);
extern int db_store_close(void *);
extern int irc_parse_message(const char *, size_t, struct irc_message *);
extern int karma_irc_event_callback(void *, const char *, size_t, const struct irc_message *);
extern int karma_sqlite_lookup(void *, const char *, size_t, struct karma_record *);

static void send_event(struct karma_event_context *ctx, const char *line) {
    struct irc_message m;
    size_t n=strlen(line);
    assert(irc_parse_message(line,n,&m)==0);
    assert(karma_irc_event_callback(ctx,line,n,&m)>=0);
}
int main(void) {
    char filename[128];
    snprintf(filename,sizeof(filename),"/tmp/sp0rkle-karma-event-%ld.db",(long)getpid());
    void *db=NULL; assert(db_store_open(filename,&db)==0);
    unsigned char bson[1024], encoded_key[256];
    char subject[128], keybuf[128], upvoter[128], downvoter[128];
    struct karma_store_context store={db,bson,sizeof(bson),encoded_key,sizeof(encoded_key),
        subject,sizeof(subject),keybuf,sizeof(keybuf),upvoter,sizeof(upvoter),
        downvoter,sizeof(downvoter)};
    struct { uint64_t offset; uint32_t length; int32_t delta; } annotations[16];
    char key_scratch[128];
    struct karma_record record_scratch;
    struct karma_event_context ctx={&store,annotations,16,key_scratch,sizeof(key_scratch),&record_scratch};

    send_event(&ctx,":Alice!u@host PRIVMSG #room :karma++ karma--\r\n");
    struct karma_record loaded={0};
    assert(karma_sqlite_lookup(&store,"karma",5,&loaded)==1);
    assert(loaded.score==0 && loaded.votes==2 && strcmp(loaded.subject,"karma")==0);
    assert(loaded.upvoter_len==5 && strcmp(loaded.upvoter,"Alice")==0);

    send_event(&ctx,":Bob!u@host PRIVMSG #room :\001ACTION thing++\001\r\n");
    assert(karma_sqlite_lookup(&store,"thing",5,&loaded)==1);
    assert(loaded.score==1 && loaded.votes==1 && strcmp(loaded.subject,"thing")==0);
    assert(strcmp(loaded.upvoter,"Bob")==0 && loaded.upvtime>0);

    send_event(&ctx,":Carol!u@host PRIVMSG #room :nothing to score\r\n");
    assert(db_store_close(db)==0);
    unlink(filename);
    puts("Karma IRC event persistence tests: PASS");
    return 0;
}
