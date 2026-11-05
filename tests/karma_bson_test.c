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
extern int bson_document_validate(const unsigned char *, size_t);
struct bson_field { const char *name; uint64_t name_len; uint32_t type; uint32_t reserved; const void *value; uint64_t value_len; };
extern int bson_document_encode(const struct bson_field *, size_t, unsigned char *, size_t, size_t *);
struct bson_find_result { uint32_t type; uint32_t reserved; const unsigned char *value; uint64_t value_len; };
extern int bson_find_field(const unsigned char *, size_t, const char *, size_t, struct bson_find_result *);

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
    assert(bson_document_validate(doc,n)==0);
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
    assert(bson_document_validate(damaged,n)==-1);
    req.doc=damaged;
    assert(karma_bson_decode(&req)==-1);

    unsigned char nested_doc[18]={18,0,0,0,0x03,'n','e','s','t','e','d',0,5,0,0,0,0,0};
    assert(bson_document_validate(nested_doc,sizeof(nested_doc))==0);
    nested_doc[12]=4;
    assert(bson_document_validate(nested_doc,sizeof(nested_doc))==-1);
    unsigned char generic[128], string_value[12]={8,0,0,0,'S','p','0','r','K','l','e',0};
    uint32_t integer_value=3;
    unsigned char empty_nested[5]={5,0,0,0,0};
    struct bson_field fields[]={
        {"name",4,0x02,0,string_value,sizeof(string_value)},
        {"score",5,0x10,0,&integer_value,sizeof(integer_value)},
        {"child",5,0x03,0,empty_nested,sizeof(empty_nested)}
    };
    size_t generic_len=0;
    assert(bson_document_encode(fields,3,generic,sizeof(generic),&generic_len)==0);
    assert(bson_document_validate(generic,generic_len)==0);
    p=field(generic,"score",0x10); assert(p && u32(p)==3);
    struct bson_find_result found={0};
    assert(bson_find_field(generic,generic_len,"score",5,&found)==1);
    assert(found.type==0x10 && found.value_len==4 && u32(found.value)==3);
    assert(bson_find_field(generic,generic_len,"missing",7,&found)==0);
    assert(found.type==0 && found.value==NULL && found.value_len==0);
    unsigned char generic_untouched[32]; memset(generic_untouched,0x33,sizeof(generic_untouched));
    size_t generic_old_len=99;
    assert(bson_document_encode(fields,3,generic_untouched,sizeof(generic_untouched),&generic_old_len)==-1);
    assert(generic_untouched[0]==0x33 && generic_old_len==99);
    puts("Karma BSON tests: PASS");
    return 0;
}
