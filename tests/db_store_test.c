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
struct batch_entry { const void *path; size_t path_len; const void *key; size_t key_len; const void *value; size_t value_len; };
extern int db_store_put_batch(void *, const struct batch_entry *, size_t);
extern int db_store_get(void *, const void *, size_t, const void *, size_t, void *, size_t, size_t *);
extern int db_store_delete(void *, const void *, size_t, const void *, size_t);
extern int db_store_sequence_next(void *, const void *, size_t, int64_t *);
extern int db_store_sequence_set(void *, const void *, size_t, int64_t);
extern int db_store_bucket_ensure(void *, const void *, size_t);
extern int db_store_bucket_exists(void *, const void *, size_t);
extern int db_store_bucket_delete(void *, const void *, size_t);
extern long db_key_path_append(const unsigned char *, size_t, const unsigned char *, size_t, unsigned char *, size_t);
extern int db_store_scan_open(void *, const void *, size_t, void **);
extern int db_store_scan_next(void *, void *, size_t, size_t *, void *, size_t, size_t *);
extern int db_store_scan_close(void *);

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
    assert(db_store_bucket_exists(db, "", 0) == 1);
    assert(db_store_bucket_delete(db, "", 0) == -1);
    const unsigned char parent_name[] = {'p', 0, 'r'};
    const unsigned char child_name[] = {'c', 0xff};
    unsigned char child_path[64] = {0};
    assert(db_store_bucket_ensure(db, parent_name, sizeof(parent_name)) == 0);
    assert(db_key_path_append(parent_name, sizeof(parent_name), child_name, sizeof(child_name), child_path, sizeof(child_path)) == 13);
    assert(db_store_bucket_ensure(db, child_path, 13) == 0);
    assert(db_store_bucket_exists(db, child_path, 13) == 1);
    assert(db_store_put(db, child_path, 13, "nested", 6, "child", 5) == 0);
    assert(db_store_put(db, parent_name, sizeof(parent_name), "parent", 6, "parent", 6) == 0);
    void *tree_cursor = NULL;
    assert(db_store_scan_tree_open(db, parent_name, sizeof(parent_name), &tree_cursor) == 0);
    unsigned char tree_path[32], tree_key[16], tree_value[16];
    size_t tree_path_len=0, tree_key_len=0, tree_value_len=0;
    struct scan_tree_entry tree_entry={tree_path,sizeof(tree_path),&tree_path_len,tree_key,sizeof(tree_key),&tree_key_len,tree_value,sizeof(tree_value),&tree_value_len};
    assert(db_store_scan_tree_next(tree_cursor,&tree_entry)==1);
    assert(tree_path_len==sizeof(parent_name) && memcmp(tree_path,parent_name,tree_path_len)==0);
    assert(tree_key_len==6 && memcmp(tree_key,"parent",6)==0);
    assert(tree_value_len==6 && memcmp(tree_value,"parent",6)==0);
    assert(db_store_scan_tree_next(tree_cursor,&tree_entry)==1);
    assert(tree_path_len==13 && memcmp(tree_path,child_path,13)==0);
    assert(tree_key_len==6 && memcmp(tree_key,"nested",6)==0);
    assert(db_store_scan_tree_next(tree_cursor,&tree_entry)==0);
    assert(db_store_scan_close(tree_cursor)==0);
    assert(db_store_bucket_delete(db, parent_name, sizeof(parent_name)) == 0);
    assert(db_store_bucket_exists(db, parent_name, sizeof(parent_name)) == 0);
    assert(db_store_bucket_exists(db, child_path, 16) == 0);
    assert(db_store_get(db, child_path, 16, "nested", 6, out, sizeof(out), &out_len) == 0);
    const unsigned char scan_path[] = {0x44};
    assert(db_store_put(db, scan_path, sizeof(scan_path), "b", 1, "B", 1) == 0);
    assert(db_store_put(db, scan_path, sizeof(scan_path), "a", 1, "A", 1) == 0);
    void *cursor = NULL;
    assert(db_store_scan_open(db, scan_path, sizeof(scan_path), &cursor) == 0);
    unsigned char scan_key[8] = {0}, scan_value[8] = {0};
    size_t scan_key_len = 0, scan_value_len = 0;
    assert(db_store_scan_next(cursor, scan_key, sizeof(scan_key), &scan_key_len, scan_value, sizeof(scan_value), &scan_value_len) == 1);
    assert(scan_key_len == 1 && scan_value_len == 1 && scan_key[0] == 'a' && scan_value[0] == 'A');
    assert(db_store_scan_next(cursor, scan_key, sizeof(scan_key), &scan_key_len, scan_value, sizeof(scan_value), &scan_value_len) == 1);
    assert(scan_key_len == 1 && scan_value_len == 1 && scan_key[0] == 'b' && scan_value[0] == 'B');
    assert(db_store_scan_next(cursor, scan_key, sizeof(scan_key), &scan_key_len, scan_value, sizeof(scan_value), &scan_value_len) == 0);
    assert(db_store_scan_close(cursor) == 0);

    assert(db_store_put(db, path, sizeof(path), key, sizeof(key), value, sizeof(value)) == 0);
    assert(db_store_get(db, path, sizeof(path), key, sizeof(key), out, sizeof(out), &out_len) == 1);
    assert(out_len == sizeof(value));
    assert(memcmp(out, value, sizeof(value)) == 0);

    assert(db_store_put(db, path, sizeof(path), "empty", 5, NULL, 0) == 0);
    assert(db_store_get(db, path, sizeof(path), "empty", 5, out, sizeof(out), &out_len) == 1);
    assert(out_len == 0);
    assert(db_store_get(db, path, sizeof(path), key, sizeof(key), out, 1, &out_len) == -1);

    int64_t sequence = 0;
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 1);
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 2);
    assert(db_store_sequence_set(db, path, sizeof(path), 41) == 0);
    assert(db_store_sequence_next(db, path, sizeof(path), &sequence) == 0 && sequence == 42);

    struct batch_entry batch[] = {
        {path,sizeof(path),"batch-a",7,"A",1},
        {path,sizeof(path),"batch-b",7,"B",1}
    };
    struct batch_entry invalid_batch[] = {
        {path,sizeof(path),"batch-a",7,"A",1},
        {path,sizeof(path),"batch-b",7,"B",1},
        {NULL,0,"bad",3,"X",1}
    };
    assert(db_store_put_batch(db, invalid_batch, 3) == -1);
    assert(db_store_get(db, path, sizeof(path), "batch-a", 7, out, sizeof(out), &out_len) == 0);
    assert(db_store_begin(db) == 0);
    assert(db_store_put_batch(db, batch, 2) == 0);
    assert(db_store_get(db, path, sizeof(path), "batch-a", 7, out, sizeof(out), &out_len) == 1);
    assert(out_len == 1 && out[0] == 'A');
    assert(db_store_rollback(db) == 0);
    assert(db_store_get(db, path, sizeof(path), "batch-a", 7, out, sizeof(out), &out_len) == 0);
    assert(db_store_put_batch(db, batch, 2) == 0);
    assert(db_store_get(db, path, sizeof(path), "batch-b", 7, out, sizeof(out), &out_len) == 1);
    assert(out_len == 1 && out[0] == 'B');

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
