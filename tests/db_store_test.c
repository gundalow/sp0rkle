#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int db_store_open(const char *, void **);
extern int db_store_close(void *);
extern int db_store_backup(void *, const char *);
extern int db_store_integrity_check(void *);
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
extern int db_store_scan_tree_open(void *, const void *, size_t, void **);
struct scan_tree_entry { void *path; size_t path_capacity; size_t *path_len; void *key; size_t key_capacity; size_t *key_len; void *value; size_t value_capacity; size_t *value_len; };
extern int db_store_scan_tree_next(void *, struct scan_tree_entry *);
extern int db_store_keyed_delete(void *, const void *, size_t, const void *, size_t, void *, size_t);
extern int db_store_keyed_scan_open(void *, const void *, size_t, const void *, size_t, void **, void *, size_t);
struct indexed_request { const void *value_path; size_t value_path_len; const void *value_key; size_t value_key_len; const void *value; size_t value_len; const struct batch_entry *old_indexes; size_t old_count; const struct batch_entry *new_indexes; size_t new_count; };
extern int db_store_indexed_update(void *, const struct indexed_request *);
struct indexed_delete_request { const void *value_path; size_t value_path_len; const void *value_key; size_t value_key_len; const struct batch_entry *old_indexes; size_t old_count; };
extern int db_store_indexed_delete(void *, const struct indexed_delete_request *);
struct indexed_get_request { const void *values_path; size_t values_path_len; const void *indexes_path; size_t indexes_path_len; const void *index_path; size_t index_path_len; const void *index_key; size_t index_key_len; void *pointer_scratch; size_t pointer_capacity; void *value_out; size_t value_capacity; size_t *value_len; };
extern int db_store_indexed_get(void *, const struct indexed_get_request *);
struct indexed_scan_request { void *statement; struct scan_tree_entry *scan_entry; const void *values_path; size_t values_path_len; void *value_out; size_t value_capacity; size_t *value_len; unsigned char *seen_ids; size_t *seen_count; size_t seen_capacity; };
extern int db_store_indexed_scan_next(void *, const struct indexed_scan_request *);

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
    assert(db_store_integrity_check(db)==0);
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
    unsigned char keyed_path[64];
    void *keyed_cursor=NULL;
    assert(db_store_keyed_scan_open(db,parent_name,sizeof(parent_name),child_name,sizeof(child_name),&keyed_cursor,keyed_path,sizeof(keyed_path))==0);
    assert(db_store_scan_tree_next(keyed_cursor,&tree_entry)==1);
    assert(tree_key_len==6 && memcmp(tree_key,"nested",6)==0);
    assert(db_store_scan_tree_next(keyed_cursor,&tree_entry)==0);
    assert(db_store_scan_close(keyed_cursor)==0);
    assert(db_store_keyed_delete(db,parent_name,sizeof(parent_name),"parent",6,keyed_path,sizeof(keyed_path))==0);
    assert(db_store_get(db,parent_name,sizeof(parent_name),"parent",6,out,sizeof(out),&out_len)==0);
    assert(db_store_keyed_delete(db,parent_name,sizeof(parent_name),child_name,sizeof(child_name),keyed_path,sizeof(keyed_path))==0);
    assert(db_store_bucket_exists(db,child_path,13)==0);
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

    const unsigned char vals_path[]="records_vals";
    const unsigned char idxs_path[]="records_idxs";
    const unsigned char object_key[]={'_','i','d',0x1f,0,1,2,3,4,5,6,7,8,9,10,11};
    const unsigned char old_index[]={'n','a','m','e',0x1f,'O','l','d'};
    const unsigned char new_index[]={'n','a','m','e',0x1f,'N','e','w'};
    const unsigned char pointer_value[]= {'_','i','d',0x1f,0,1,2,3,4,5,6,7,8,9,10,11};
    struct batch_entry first_index={idxs_path,sizeof(idxs_path)-1,old_index,sizeof(old_index),pointer_value,sizeof(pointer_value)};
    struct indexed_request indexed={vals_path,sizeof(vals_path)-1,object_key,sizeof(object_key),"record-one",10,NULL,0,&first_index,1};
    assert(db_store_indexed_update(db,&indexed)==0);
    assert(db_store_get(db,vals_path,sizeof(vals_path)-1,object_key,sizeof(object_key),out,sizeof(out),&out_len)==1);
    assert(out_len==10 && memcmp(out,"record-one",10)==0);
    assert(db_store_get(db,idxs_path,sizeof(idxs_path)-1,old_index,sizeof(old_index),out,sizeof(out),&out_len)==1);
    struct batch_entry old_index_entry=first_index;
    struct batch_entry next_index={idxs_path,sizeof(idxs_path)-1,new_index,sizeof(new_index),pointer_value,sizeof(pointer_value)};
    indexed.value="record-two"; indexed.value_len=10; indexed.old_indexes=&old_index_entry; indexed.old_count=1; indexed.new_indexes=&next_index;
    assert(db_store_indexed_update(db,&indexed)==0);
    assert(db_store_get(db,idxs_path,sizeof(idxs_path)-1,old_index,sizeof(old_index),out,sizeof(out),&out_len)==0);
    assert(db_store_get(db,idxs_path,sizeof(idxs_path)-1,new_index,sizeof(new_index),out,sizeof(out),&out_len)==1);
    unsigned char pointer_scratch[32], indexed_value[32]; size_t indexed_value_len=0;
    struct indexed_get_request index_get={vals_path,sizeof(vals_path)-1,idxs_path,sizeof(idxs_path)-1,idxs_path,sizeof(idxs_path)-1,new_index,sizeof(new_index),pointer_scratch,sizeof(pointer_scratch),indexed_value,sizeof(indexed_value),&indexed_value_len};
    assert(db_store_indexed_get(db,&index_get)==1);
    assert(indexed_value_len==10 && memcmp(indexed_value,"record-two",10)==0);
    index_get.index_path_len=0; index_get.index_key=object_key; index_get.index_key_len=sizeof(object_key);
    assert(db_store_indexed_get(db,&index_get)==1);
    assert(indexed_value_len==10 && memcmp(indexed_value,"record-two",10)==0);
    struct batch_entry bad_index={NULL,0,"bad",3,pointer_value,sizeof(pointer_value)};
    indexed.value="record-bad"; indexed.old_indexes=&next_index; indexed.new_indexes=&bad_index;
    assert(db_store_indexed_update(db,&indexed)==-1);
    assert(db_store_get(db,vals_path,sizeof(vals_path)-1,object_key,sizeof(object_key),out,sizeof(out),&out_len)==1);
    assert(out_len==10 && memcmp(out,"record-two",10)==0);
    assert(db_store_get(db,idxs_path,sizeof(idxs_path)-1,new_index,sizeof(new_index),out,sizeof(out),&out_len)==1);
    const unsigned char alias_index[]={'n','a','m','e',0x1f,'A','l','i','a','s'};
    struct batch_entry alias_entry={idxs_path,sizeof(idxs_path)-1,alias_index,sizeof(alias_index),pointer_value,sizeof(pointer_value)};
    assert(db_store_put(db,idxs_path,sizeof(idxs_path)-1,alias_index,sizeof(alias_index),pointer_value,sizeof(pointer_value))==0);
    void *index_cursor=NULL;
    assert(db_store_scan_tree_open(db,idxs_path,sizeof(idxs_path)-1,&index_cursor)==0);
    unsigned char scan_index_path[32],scan_index_key[32],scan_pointer[32],seen_ids[64];
    size_t scan_index_path_len=0,scan_index_key_len=0,scan_pointer_len=0,seen_count=0,indexed_scan_len=0;
    struct scan_tree_entry scan_descriptor={scan_index_path,sizeof(scan_index_path),&scan_index_path_len,scan_index_key,sizeof(scan_index_key),&scan_index_key_len,scan_pointer,sizeof(scan_pointer),&scan_pointer_len};
    struct indexed_scan_request scan_request={index_cursor,&scan_descriptor,vals_path,sizeof(vals_path)-1,indexed_value,sizeof(indexed_value),&indexed_scan_len,seen_ids,&seen_count,4};
    assert(db_store_indexed_scan_next(db,&scan_request)==1);
    assert(indexed_scan_len==10 && memcmp(indexed_value,"record-two",10)==0 && seen_count==1);
    assert(db_store_indexed_scan_next(db,&scan_request)==0);
    assert(db_store_scan_close(index_cursor)==0);
    struct batch_entry delete_indexes[]={next_index,alias_entry};
    struct indexed_delete_request indexed_delete={vals_path,sizeof(vals_path)-1,object_key,sizeof(object_key),delete_indexes,2};
    assert(db_store_indexed_delete(db,&indexed_delete)==0);
    assert(db_store_get(db,vals_path,sizeof(vals_path)-1,object_key,sizeof(object_key),out,sizeof(out),&out_len)==0);
    assert(db_store_get(db,idxs_path,sizeof(idxs_path)-1,new_index,sizeof(new_index),out,sizeof(out),&out_len)==0);

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
    char backup_filename[128];
    snprintf(backup_filename,sizeof(backup_filename),"/tmp/sp0rkle-kv-backup-%ld.db",(long)getpid());
    assert(db_store_backup(db,backup_filename)==0);
    assert(db_store_close(db) == 0);

    void *backup_db=NULL;
    assert(db_store_open(backup_filename,&backup_db)==0);
    assert(db_store_get(backup_db,path,sizeof(path),"committed",9,out,sizeof(out),&out_len)==1);
    assert(memcmp(out,transient,sizeof(transient))==0);
    assert(db_store_close(backup_db)==0);
    unlink(backup_filename);

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
