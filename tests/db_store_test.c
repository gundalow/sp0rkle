#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int db_store_open(const char *, void **);
extern int db_store_close(void *);
extern int db_store_begin(void *);
extern int db_store_commit(void *);
extern int db_store_rollback(void *);
extern int db_store_put(void *, const void *, size_t, const void *, size_t, const void *, size_t);
extern int db_store_get(void *, const void *, size_t, const void *, size_t, void *, size_t, size_t *);
extern int db_store_delete(void *, const void *, size_t, const void *, size_t);
extern int db_store_sequence_next(void *, const void *, size_t, int64_t *);
extern int db_store_sequence_set(void *, const void *, size_t, int64_t);

int main(void) {
    char filename[] = "/tmp/sp0rkle-kv-XXXXXX";
    int fd = mkstemp(filename);
    assert(fd >= 0);
    close(fd);

    const unsigned char path[] = {0x01, 0x00, 0x02};
    const unsigned char key[] = {0x1f, 0x00, 0xff};
    const unsigned char value[] = {'v', 0, 'a', 'l', 0xff};
    unsigned char out[32] = {0};
    size_t out_len = 0;
    void *db = NULL;

    assert(db_store_open(filename, &db) == 0);
    assert(db != NULL);
    assert(db_store_put(db, path, sizeof(path), key, sizeof(key), value, sizeof(value)) == 0);
    assert(db_store_get(db, path, sizeof(path), key, sizeof(key), out, sizeof(out), &out_len) == 1);
    assert(out_len == sizeof(value));
    assert(memcmp(out, value, sizeof(value)) == 0);

    int64_t sequence = 0;
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 1);
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 2);
    assert(db_store_sequence_set(db, path, sizeof(path), 41) == 0);
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 42);

    assert(db_store_begin(db) == 0);
    const unsigned char transient[] = "rollback";
    assert(db_store_put(db, path, sizeof(path), "temporary", 9, transient, sizeof(transient)) == 0);
    assert(db_store_rollback(db) == 0);
    assert(db_store_get(db, path, sizeof(path), "temporary", 9, out, sizeof(out), &out_len) == 0);

    assert(db_store_begin(db) == 0);
    assert(db_store_put(db, path, sizeof(path), "committed", 9, transient, sizeof(transient)) == 0);
    assert(db_store_commit(db) == 0);
    assert(db_store_close(db) == 0);

    db = NULL;
    assert(db_store_open(filename, &db) == 0);
    memset(out, 0, sizeof(out));
    assert(db_store_get(db, path, sizeof(path), key, sizeof(key), out, sizeof(out), &out_len) == 1);
    assert(out_len == sizeof(value));
    assert(memcmp(out, value, sizeof(value)) == 0);
    assert(db_store_get(db, path, sizeof(path), "committed", 9, out, sizeof(out), &out_len) == 1);
    assert(memcmp(out, transient, sizeof(transient)) == 0);
    assert(db_store_delete(db, path, sizeof(path), key, sizeof(key)) == 0);
    assert(db_store_get(db, path, sizeof(path), key, sizeof(key), out, sizeof(out), &out_len) == 0);
    assert(db_store_close(db) == 0);

    unlink(filename);
    puts("SQLite storage tests: PASS");
    return 0;
}
