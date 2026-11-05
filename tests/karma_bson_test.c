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
    puts("Karma BSON tests: PASS");
    return 0;
}
