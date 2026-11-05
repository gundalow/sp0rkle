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
extern int karma_bson_encode(const struct karma_record *, unsigned char *, size_t, size_t *);
struct decode_request {
    const unsigned char *doc; uint64_t doc_len; struct karma_record *record;
    char *subject; uint64_t subject_capacity;
    char *key; uint64_t key_capacity;
    char *upvoter; uint64_t upvoter_capacity;
    char *downvoter; uint64_t downvoter_capacity;
};
extern int karma_bson_decode(struct decode_request *);

static uint32_t u32(const unsigned char *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static uint64_t u64(const unsigned char *p) {
    uint64_t v=0; for (int i=7;i>=0;i--) v=(v<<8)|p[i]; return v;
}
static const unsigned char *field(const unsigned char *doc, const char *name, unsigned char type) {
    const unsigned char *p=doc+4, *end=doc+u32(doc)-1;
    while (p<end && *p) {
        unsigned char t=*p++;
        const char *n=(const char *)p;
        size_t nl=strlen(n);
        p+=nl+1;
        if (t==type && strcmp(n,name)==0) return p;
        switch(t) {
        case 0x02: p+=4+u32(p); break;
        case 0x10: p+=4; break;
        case 0x12: case 0x09: p+=8; break;
        default: assert(!"unexpected BSON type");
        }
    }
    return NULL;
}
int main(void) {
    struct karma_record r={.subject="Sp0rKle",.subject_len=7,.key="sp0rkle",
        .score=1,.votes=2,.upvoter="Alice",.upvoter_len=5,.upvtime=1000,
        .downvoter="Bob",.downvoter_len=3,.downvtime=2000};
    unsigned char doc[256]; memset(doc,0xa5,sizeof(doc));
    size_t n=0;
    assert(karma_bson_encode(&r,doc,sizeof(doc),&n)==0);
    assert(n==u32(doc) && doc[n-1]==0);
    const unsigned char *p=field(doc,"subject",0x02);
    assert(p && u32(p)==8 && memcmp(p+4,"Sp0rKle",7)==0 && p[11]==0);
    p=field(doc,"key",0x02);
    assert(p && u32(p)==8 && memcmp(p+4,"sp0rkle",7)==0);
    p=field(doc,"score",0x10); assert(p && u32(p)==1);
    p=field(doc,"votes",0x10); assert(p && u32(p)==2);
    p=field(doc,"upvoter",0x02); assert(p && u32(p)==6 && memcmp(p+4,"Alice",5)==0);
    p=field(doc,"upvtime",0x09); assert(p && (int64_t)u64(p)==1000);
    p=field(doc,"downvoter",0x02); assert(p && u32(p)==4 && memcmp(p+4,"Bob",3)==0);
    p=field(doc,"downvtime",0x09); assert(p && (int64_t)u64(p)==2000);

    unsigned char untouched[256]; memset(untouched,0x5a,sizeof(untouched));
    size_t old_len=777;
    assert(karma_bson_encode(&r,untouched,1,&old_len)==-1);
    assert(untouched[0]==0x5a && old_len==777);

    r.score=INT64_C(2147483648);
    assert(karma_bson_encode(&r,doc,sizeof(doc),&n)==0);
    p=field(doc,"score",0x12); assert(p && (int64_t)u64(p)==INT64_C(2147483648));

    struct karma_record decoded={0};
    char subject[32], key[32], upvoter[32], downvoter[32];
    struct decode_request req={doc,n,&decoded,subject,sizeof(subject),key,sizeof(key),
        upvoter,sizeof(upvoter),downvoter,sizeof(downvoter)};
    assert(karma_bson_decode(&req)==0);
    assert(strcmp(subject,"Sp0rKle")==0 && strcmp(key,"sp0rkle")==0);
    assert(decoded.subject==subject && decoded.subject_len==7 && decoded.key==key);
    assert(decoded.score==INT64_C(2147483648) && decoded.votes==2);
    assert(strcmp(upvoter,"Alice")==0 && decoded.upvoter_len==5 && decoded.upvtime==1000);
    assert(strcmp(downvoter,"Bob")==0 && decoded.downvoter_len==3 && decoded.downvtime==2000);
    struct decode_request small=req; small.subject_capacity=2;
    assert(karma_bson_decode(&small)==-1);
    unsigned char damaged[256]; memcpy(damaged,doc,n); damaged[n-1]=1;
    req.doc=damaged;
    assert(karma_bson_decode(&req)==-1);

    puts("Karma BSON tests: PASS");
    return 0;
}
