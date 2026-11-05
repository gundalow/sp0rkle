#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern int db_key_validate_name(const char *, size_t);
extern long db_key_encode_string(const char *, size_t, const char *, size_t, unsigned char *, size_t);
extern long db_key_encode_u64(const char *, size_t, uint64_t, unsigned char *, size_t);
extern long db_key_encode_bool(const char *, size_t, int, unsigned char *, size_t);
extern long db_key_encode_id(const unsigned char *, unsigned char *, size_t);
extern long db_key_encode_timestamp_ms(const char *, size_t, int64_t, unsigned char *, size_t);
extern long db_key_path_append(const unsigned char *, size_t, const unsigned char *, size_t, unsigned char *, size_t);
int main(void) {
    unsigned char out[64] = {0};
    assert(db_key_validate_name("valid", 5) == 0);
    assert(db_key_validate_name("bad\x1fname", 8) == -1);
    assert(db_key_encode_string("name", 4, "value", 5, out, sizeof(out)) == 10);
    assert(memcmp(out, "name\x1fvalue", 10) == 0);
    assert(db_key_encode_u64("count", 5, UINT64_C(0x0102030405060708), out, sizeof(out)) == 14);
    const unsigned char expected[] = {'c','o','u','n','t',0x1f,1,2,3,4,5,6,7,8};
    assert(memcmp(out, expected, sizeof(expected)) == 0);
    assert(db_key_encode_bool("flag", 4, 1, out, sizeof(out)) == 6);
    assert(memcmp(out, "flag\x1f\xff", 6) == 0);
    assert(db_key_encode_bool("flag", 4, 0, out, sizeof(out)) == 6);
    assert(memcmp(out, "flag\x1f\x00", 6) == 0);
    const unsigned char object_id[12] = {0,1,2,3,4,5,6,7,8,9,10,11};
    assert(db_key_encode_id(object_id, out, sizeof(out)) == 16);
    const unsigned char id_expected[] = {'_', 'i', 'd', 0x1f, 0,1,2,3,4,5,6,7,8,9,10,11};
    assert(memcmp(out, id_expected, sizeof(id_expected)) == 0);
    assert(db_key_encode_id(object_id, out, 15) == -1);
    assert(db_key_encode_timestamp_ms("when", 4, INT64_C(-1), out, sizeof(out)) == 13);
    const unsigned char ts_expected[] = {'w','h','e','n',0x1f,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
    assert(memcmp(out, ts_expected, sizeof(ts_expected)) == 0);
    const unsigned char parent_path[] = {0xaa};
    const unsigned char child_elem[] = {0x1f, 0x00};
    unsigned char path_out[32] = {0};
    assert(db_key_path_append(parent_path, sizeof(parent_path), child_elem, sizeof(child_elem), path_out, sizeof(path_out)) == 11);
    const unsigned char path_expected[] = {0xaa,0,0,0,0,0,0,0,2,0x1f,0};
    assert(memcmp(path_out, path_expected, sizeof(path_expected)) == 0);
    memset(path_out, 0x55, sizeof(path_out));
    assert(db_key_path_append(parent_path, sizeof(parent_path), child_elem, sizeof(child_elem), path_out, 10) == -1);
    assert(path_out[0] == 0x55);
    memset(out, 0x55, sizeof(out));
    assert(db_key_encode_string("name", 4, "value", 5, out, 9) == -1);
    assert(out[0] == 0x55);
    assert(db_key_encode_u64("bad\x1f", 4, 1, out, sizeof(out)) == -1);
    assert(db_key_encode_bool("flag", 4, 1, out, 5) == -1);
    puts("Database key encoding tests: PASS");
    return 0;
}
