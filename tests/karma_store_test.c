#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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
struct annotation { uint64_t offset; uint32_t length; int32_t delta; };
struct apply_request {
    const char *text; uint64_t text_len;
    const struct annotation *items; uint64_t count;
    const char *voter; uint64_t voter_len; int64_t timestamp;
    int (*lookup)(void *, const char *, size_t, struct karma_record *);
    int (*put)(void *, const struct karma_record *);
    void *ctx; char *key; uint64_t key_capacity;
    struct karma_record *record;
};
extern int db_store_open(const char *, void **);
extern int db_store_close(void *);
extern int karma_sqlite_lookup(void *, const char *, size_t, struct karma_record *);
extern int karma_sqlite_put(void *, const struct karma_record *);
extern long karma_parse_annotations(const char *, size_t, struct annotation *, size_t);
extern long karma_apply_annotations(const struct apply_request *);

int main(void) {
    char filename[]="/tmp/sp0rkle-karma-store-XXXXXX";
    int fd=mkstemp(filename); assert(fd>=0); close(fd);
    void *db=NULL; assert(db_store_open(filename,&db)==0);
    unsigned char bson[1024], encoded_key[256];
    char subject[128], keybuf[128], upvoter[128], downvoter[128];
    struct karma_store_context ctx={db,bson,sizeof(bson),encoded_key,sizeof(encoded_key),
        subject,sizeof(subject),keybuf,sizeof(keybuf),upvoter,sizeof(upvoter),
        downvoter,sizeof(downvoter)};

    const char text[]="karma++ karma--";
    struct annotation items[4];
    assert(karma_parse_annotations(text,sizeof(text)-1,items,4)==2);
    char apply_key[64];
    struct karma_record scratch={0};
    struct apply_request req={text,sizeof(text)-1,items,2,"Alice",5,1234,
        karma_sqlite_lookup,karma_sqlite_put,&ctx,apply_key,sizeof(apply_key),&scratch};
    assert(karma_apply_annotations(&req)==2);

    struct karma_record loaded={0};
    assert(karma_sqlite_lookup(&ctx,"karma",5,&loaded)==1);
    assert(strcmp(loaded.subject,"karma")==0 && strcmp(loaded.key,"karma")==0);
    assert(loaded.score==0 && loaded.votes==2);
    assert(strcmp(loaded.upvoter,"Alice")==0 && loaded.upvtime==1234);
    assert(strcmp(loaded.downvoter,"Alice")==0 && loaded.downvtime==1234);

    assert(db_store_close(db)==0);
    unlink(filename);
    puts("Karma SQLite persistence tests: PASS");
    return 0;
}
