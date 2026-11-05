default rel

global db_store_open
global db_store_close
global db_store_begin
global db_store_commit
global db_store_rollback
global db_store_put
global db_store_put_batch
global db_store_get
global db_store_delete
global db_store_sequence_next
global db_store_sequence_set
global db_store_bucket_ensure
global db_store_bucket_exists
global db_store_bucket_delete
global db_store_scan_open
global db_store_scan_tree_open
global db_store_scan_tree_next
global db_store_scan_next
global db_store_scan_close

extern sqlite3_open_v2
extern sqlite3_busy_timeout
extern sqlite3_close
extern sqlite3_exec
extern sqlite3_free
extern sqlite3_prepare_v2
extern sqlite3_bind_blob
extern sqlite3_step
extern sqlite3_finalize
extern sqlite3_column_blob
extern sqlite3_column_bytes
extern sqlite3_column_int64
extern sqlite3_bind_int64

%define SQLITE_OPEN_READWRITE 0x00000002
%define SQLITE_OPEN_CREATE    0x00000004
%define SQLITE_OPEN_FULLMUTEX 0x00010000
%define SQLITE_OK             0
%define SQLITE_ROW            100
%define SQLITE_DONE           101
%define SQLITE_TRANSIENT      -1

section .rodata
schema_sql: db "PRAGMA journal_mode=WAL;"
            db "CREATE TABLE IF NOT EXISTS kv (path BLOB NOT NULL, key BLOB NOT NULL, value BLOB NOT NULL, PRIMARY KEY(path,key)) WITHOUT ROWID;"
            db "CREATE TABLE IF NOT EXISTS sequences (path BLOB PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID;"
            db "CREATE TABLE IF NOT EXISTS buckets (path BLOB PRIMARY KEY NOT NULL) WITHOUT ROWID;"
            db "INSERT OR IGNORE INTO buckets(path) VALUES(x'');", 0
begin_sql: db "BEGIN IMMEDIATE", 0
commit_sql: db "COMMIT", 0
rollback_sql: db "ROLLBACK", 0
put_sql: db "INSERT INTO kv(path,key,value) VALUES(?1,?2,?3) ON CONFLICT(path,key) DO UPDATE SET value=excluded.value", 0
get_sql: db "SELECT value FROM kv WHERE path=?1 AND key=?2", 0
empty_blob: db 0
delete_sql: db "DELETE FROM kv WHERE path=?1 AND key=?2", 0
seq_next_sql: db "INSERT INTO sequences(path,value) VALUES(?1,1) ON CONFLICT(path) DO UPDATE SET value=value+1 RETURNING value", 0
seq_set_sql: db "INSERT INTO sequences(path,value) VALUES(?1,?2) ON CONFLICT(path) DO UPDATE SET value=excluded.value", 0
bucket_ensure_sql: db "INSERT OR IGNORE INTO buckets(path) VALUES(?1)", 0
bucket_exists_sql: db "SELECT 1 FROM buckets WHERE path=?1", 0
bucket_delete_kv_sql: db "DELETE FROM kv WHERE substr(path,1,?1)=?2", 0
bucket_delete_seq_sql: db "DELETE FROM sequences WHERE substr(path,1,?1)=?2", 0
bucket_delete_bucket_sql: db "DELETE FROM buckets WHERE substr(path,1,?1)=?2", 0
scan_sql: db "SELECT key,value FROM kv WHERE path=?1 ORDER BY key", 0
scan_tree_sql: db "SELECT path,key,value FROM kv WHERE substr(path,1,?1)=?2 ORDER BY path,key", 0
savepoint_sql: db "SAVEPOINT bucket_delete", 0
rollback_savepoint_sql: db "ROLLBACK TO bucket_delete", 0
release_sql: db "RELEASE bucket_delete", 0
batch_savepoint_sql: db "SAVEPOINT batch_put", 0
batch_rollback_sql: db "ROLLBACK TO batch_put", 0
batch_release_sql: db "RELEASE batch_put", 0

section .text
; int db_store_open(path, sqlite_handle_out)
; Creates a durable SQLite-backed binary key/value store. The caller owns the
; returned handle and must close it. Returns 0 on success, -1 on failure.
db_store_open:
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .open_error
    test r13, r13
    jz .open_error
    mov qword [rsp], 0
    mov qword [rsp + 8], 0
    mov rdi, r12
    lea rsi, [rsp]
    mov edx, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    xor ecx, ecx
    call sqlite3_open_v2
    test eax, eax
    jnz .open_close_partial
    mov rbx, [rsp]
    mov rdi, rbx
    mov esi, 5000
    call sqlite3_busy_timeout
    test eax, eax
    jnz .open_close_partial
    mov rdi, rbx
    lea rsi, [rel schema_sql]
    xor edx, edx
    xor ecx, ecx
    lea r8, [rsp + 8]
    call sqlite3_exec
    test eax, eax
    jnz .open_close_partial
    mov [r13], rbx
    xor eax, eax
    jmp .open_done
.open_close_partial:
    mov rax, [rsp + 8]
    test rax, rax
    jz .open_no_error_message
    mov rdi, rax
    call sqlite3_free
.open_no_error_message:
    mov rbx, [rsp]
    test rbx, rbx
    jz .open_error
    mov rdi, rbx
    call sqlite3_close
.open_error:
    mov eax, -1
.open_done:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_close(handle)
db_store_close:
    test rdi, rdi
    jz .close_error
    jmp sqlite3_close
.close_error:
    mov eax, -1
    ret

; Internal: int db_store_exec(handle, sql)
db_store_exec:
    ; Entry stack is 8 mod 16; align before calling SQLite.
    sub rsp, 8
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call sqlite3_exec
    add rsp, 8
    test eax, eax
    jz .exec_ok
    mov eax, -1
    ret
.exec_ok:
    xor eax, eax
    ret

db_store_begin:
    lea rsi, [rel begin_sql]
    jmp db_store_exec

db_store_commit:
    lea rsi, [rel commit_sql]
    jmp db_store_exec

db_store_rollback:
    lea rsi, [rel rollback_sql]
    jmp db_store_exec

; int db_store_put(handle,path,path_len,key,key_len,value,value_len)
; Upserts one binary value. Path and key are opaque byte strings; callers
; encode hierarchical bucket paths using their own length-delimited format.
db_store_put:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rsp], r9
    mov rax, [rsp + 80]
    mov [rsp + 8], rax
    mov qword [rsp + 16], 0
    test r12, r12
    jz .put_error
    test r13, r13
    jz .put_error
    test r15, r15
    jz .put_error
    ; A zero-length value is valid; non-zero values require a pointer.
    cmp qword [rsp + 8], 0
    je .put_prepare
    cmp qword [rsp], 0
    je .put_error
.put_prepare:
    mov rdi, r12
    lea rsi, [rel put_sql]
    mov edx, -1
    lea rcx, [rsp + 16]
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .put_error
    mov rdi, [rsp + 16]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .put_finalize_error
    mov rdi, [rsp + 16]
    mov esi, 2
    mov rdx, r15
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .put_finalize_error
    mov rdi, [rsp + 16]
    mov esi, 3
    mov rdx, [rsp]
    cmp qword [rsp + 8], 0
    jne .put_value_pointer_ready
    lea rdx, [rel empty_blob]
.put_value_pointer_ready:
    mov rcx, [rsp + 8]
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .put_finalize_error
    mov rdi, [rsp + 16]
    call sqlite3_step
    cmp eax, SQLITE_DONE
    jne .put_finalize_error
    mov rdi, [rsp + 16]
    call sqlite3_finalize
    test eax, eax
    jnz .put_error
    xor eax, eax
    jmp .put_done
.put_finalize_error:
    mov rdi, [rsp + 16]
    call sqlite3_finalize
.put_error:
    mov eax, -1
.put_done:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_get(handle,path,path_len,key,key_len,out,capacity,out_len)
; Returns 1 when found, 0 when absent, -1 on error/capacity failure.
db_store_get:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rsp], r9
    mov rax, [rbp + 16]
    mov [rsp + 8], rax
    mov rax, [rbp + 24]
    mov [rsp + 16], rax
    mov qword [rsp + 24], 0
    mov rax, [rsp + 16]
    test rax, rax
    jz .get_error
    mov qword [rax], 0
    test r12, r12
    jz .get_error
    test r13, r13
    jz .get_error
    test r15, r15
    jz .get_error
    mov rdi, r12
    lea rsi, [rel get_sql]
    mov edx, -1
    lea rcx, [rsp + 24]
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .get_error
    mov rdi, [rsp + 24]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .get_finalize_error
    mov rdi, [rsp + 24]
    mov esi, 2
    mov rdx, r15
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .get_finalize_error
    mov rdi, [rsp + 24]
    call sqlite3_step
    cmp eax, SQLITE_ROW
    je .get_row
    cmp eax, SQLITE_DONE
    je .get_missing
    jmp .get_finalize_error
.get_row:
    mov rdi, [rsp + 24]
    xor esi, esi
    call sqlite3_column_bytes
    mov [rsp + 32], rax
    cmp rax, [rsp + 8]
    ja .get_finalize_error
    test rax, rax
    jz .get_copy_done
    cmp qword [rsp], 0
    je .get_finalize_error
    mov rdi, [rsp + 24]
    xor esi, esi
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, [rsp]
    mov rcx, [rsp + 32]
    rep movsb
.get_copy_done:
    mov rax, [rsp + 16]
    test rax, rax
    jz .get_finalize_error
    mov rcx, [rsp + 32]
    mov [rax], rcx
    mov rdi, [rsp + 24]
    call sqlite3_finalize
    test eax, eax
    jnz .get_error
    mov eax, 1
    jmp .get_done
.get_missing:
    mov rdi, [rsp + 24]
    call sqlite3_finalize
    test eax, eax
    jnz .get_error
    xor eax, eax
    jmp .get_done
.get_finalize_error:
    mov rdi, [rsp + 24]
    call sqlite3_finalize
.get_error:
    mov eax, -1
.get_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int db_store_delete(handle,path,path_len,key,key_len)
; Returns 0 on success (including absent key), -1 on error.
db_store_delete:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov qword [rsp], 0
    test r12, r12
    jz .delete_error
    test r13, r13
    jz .delete_error
    test r15, r15
    jz .delete_error
    mov rdi, r12
    lea rsi, [rel delete_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .delete_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .delete_finalize_error
    mov rdi, [rsp]
    mov esi, 2
    mov rdx, r15
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .delete_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_DONE
    jne .delete_finalize_error
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .delete_error
    xor eax, eax
    jmp .delete_done
.delete_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.delete_error:
    mov eax, -1
.delete_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_sequence_next(handle,path,path_len,value_out)
; Atomically increments a per-path sequence (first result is 1).
db_store_sequence_next:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    mov qword [rsp], 0
    test r12, r12
    jz .seq_next_error
    test r13, r13
    jz .seq_next_error
    test rbx, rbx
    jz .seq_next_error
    mov rdi, r12
    lea rsi, [rel seq_next_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .seq_next_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .seq_next_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_ROW
    jne .seq_next_finalize_error
    mov rdi, [rsp]
    xor esi, esi
    call sqlite3_column_int64
    mov [rbx], rax
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .seq_next_error
    xor eax, eax
    jmp .seq_next_done
.seq_next_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.seq_next_error:
    mov eax, -1
.seq_next_done:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_sequence_set(handle,path,path_len,value)
; Sets the sequence to an exact signed 64-bit value.
db_store_sequence_set:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    mov qword [rsp], 0
    test r12, r12
    jz .seq_set_error
    test r13, r13
    jz .seq_set_error
    mov rdi, r12
    lea rsi, [rel seq_set_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .seq_set_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .seq_set_finalize_error
    mov rdi, [rsp]
    mov esi, 2
    mov rdx, rbx
    call sqlite3_bind_int64
    test eax, eax
    jnz .seq_set_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_DONE
    jne .seq_set_finalize_error
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .seq_set_error
    xor eax, eax
    jmp .seq_set_done
.seq_set_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.seq_set_error:
    mov eax, -1
.seq_set_done:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_bucket_ensure(handle,path,path_len)
; Creates one exact bucket path. Parent paths are created by the caller.
db_store_bucket_ensure:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov qword [rsp], 0
    test r12, r12
    jz .bucket_ensure_error
    test r13, r13
    jz .bucket_ensure_error
    mov rdi, r12
    lea rsi, [rel bucket_ensure_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .bucket_ensure_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .bucket_ensure_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_DONE
    jne .bucket_ensure_finalize_error
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .bucket_ensure_error
    xor eax, eax
    jmp .bucket_ensure_done
.bucket_ensure_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.bucket_ensure_error:
    mov eax, -1
.bucket_ensure_done:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_bucket_exists(handle,path,path_len)
; Returns 1 if present, 0 if absent, -1 on error.
db_store_bucket_exists:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov qword [rsp], 0
    test r12, r12
    jz .bucket_exists_error
    test r13, r13
    jz .bucket_exists_error
    mov rdi, r12
    lea rsi, [rel bucket_exists_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .bucket_exists_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .bucket_exists_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_ROW
    je .bucket_exists_found
    cmp eax, SQLITE_DONE
    jne .bucket_exists_finalize_error
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .bucket_exists_error
    xor eax, eax
    jmp .bucket_exists_done
.bucket_exists_found:
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .bucket_exists_error
    mov eax, 1
    jmp .bucket_exists_done
.bucket_exists_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.bucket_exists_error:
    mov eax, -1
.bucket_exists_done:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; Internal: int db_store_delete_prefix(handle, sql, path, path_len)
db_store_delete_prefix:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rbx, rcx
    mov qword [rsp], 0
    mov rdi, r12
    mov rsi, r13
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .delete_prefix_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, rbx
    call sqlite3_bind_int64
    test eax, eax
    jnz .delete_prefix_finalize_error
    mov rdi, [rsp]
    mov esi, 2
    mov rdx, r14
    mov rcx, rbx
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .delete_prefix_finalize_error
    mov rdi, [rsp]
    call sqlite3_step
    cmp eax, SQLITE_DONE
    jne .delete_prefix_finalize_error
    mov rdi, [rsp]
    call sqlite3_finalize
    test eax, eax
    jnz .delete_prefix_error
    xor eax, eax
    jmp .delete_prefix_done
.delete_prefix_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.delete_prefix_error:
    mov eax, -1
.delete_prefix_done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_bucket_delete(handle,path,path_len)
; Recursively removes this bucket and descendants, including stored values
; and sequences. The root path is protected. Uses a savepoint so it can nest
; inside a caller transaction.
db_store_bucket_delete:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test r12, r12
    jz .bucket_delete_error
    test r13, r13
    jz .bucket_delete_error
    test r14, r14
    jz .bucket_delete_error
    mov rdi, r12
    lea rsi, [rel savepoint_sql]
    call db_store_exec
    test eax, eax
    jnz .bucket_delete_error
    mov rdi, r12
    lea rsi, [rel bucket_delete_kv_sql]
    mov rdx, r13
    mov rcx, r14
    call db_store_delete_prefix
    test eax, eax
    jnz .bucket_delete_rollback
    mov rdi, r12
    lea rsi, [rel bucket_delete_seq_sql]
    mov rdx, r13
    mov rcx, r14
    call db_store_delete_prefix
    test eax, eax
    jnz .bucket_delete_rollback
    mov rdi, r12
    lea rsi, [rel bucket_delete_bucket_sql]
    mov rdx, r13
    mov rcx, r14
    call db_store_delete_prefix
    test eax, eax
    jnz .bucket_delete_rollback
    mov rdi, r12
    lea rsi, [rel release_sql]
    call db_store_exec
    test eax, eax
    jnz .bucket_delete_rollback
    xor eax, eax
    jmp .bucket_delete_done
.bucket_delete_rollback:
    mov rdi, r12
    lea rsi, [rel rollback_savepoint_sql]
    call db_store_exec
    mov rdi, r12
    lea rsi, [rel release_sql]
    call db_store_exec
.bucket_delete_error:
    mov eax, -1
.bucket_delete_done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_scan_open(handle,path,path_len,statement_out)
; Opens a stable SQLite read cursor over one bucket, ordered by binary key.
db_store_scan_open:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov qword [rsp], 0
    test r12, r12
    jz .scan_open_error
    test r13, r13
    jz .scan_open_error
    test rcx, rcx
    jz .scan_open_error
    mov rdi, r12
    lea rsi, [rel scan_sql]
    mov edx, -1
    lea rcx, [rsp]
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .scan_open_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .scan_open_finalize_error
    mov rax, [rsp]
    mov [r15], rax
    xor eax, eax
    jmp .scan_open_done
.scan_open_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.scan_open_error:
    mov eax, -1
.scan_open_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_scan_next(stmt,key_out,key_capacity,key_len_out,value_out,
;                        value_capacity,value_len_out)
; Returns 1 for a row, 0 at end, -1 on error/capacity failure.
db_store_scan_next:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov [rsp], r9
    mov rax, [rbp + 16]
    mov [rsp + 8], rax
    test r12, r12
    jz .scan_next_error
    test r15, r15
    jz .scan_next_error
    cmp qword [rsp + 8], 0
    je .scan_next_error
    mov rdi, r12
    call sqlite3_step
    cmp eax, SQLITE_ROW
    je .scan_next_row
    cmp eax, SQLITE_DONE
    je .scan_next_end
    jmp .scan_next_error
.scan_next_row:
    mov rdi, r12
    xor esi, esi
    call sqlite3_column_bytes
    mov [rsp + 24], rax
    cmp rax, r14
    ja .scan_next_error
    test rax, rax
    jz .scan_next_key_done
    test r13, r13
    jz .scan_next_error
    mov rdi, r12
    xor esi, esi
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, r13
    mov rcx, [rsp + 24]
    rep movsb
.scan_next_key_done:
    mov rdi, r12
    mov esi, 1
    call sqlite3_column_bytes
    mov [rsp + 32], rax
    cmp rax, [rsp]
    ja .scan_next_error
    test rax, rax
    jz .scan_next_value_done
    test rbx, rbx
    jz .scan_next_error
    mov rdi, r12
    mov esi, 1
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, rbx
    mov rcx, [rsp + 32]
    rep movsb
.scan_next_value_done:
    mov rcx, [rsp + 24]
    mov [r15], rcx
    mov rax, [rsp + 8]
    mov rcx, [rsp + 32]
    mov [rax], rcx
    mov eax, 1
    jmp .scan_next_done
.scan_next_end:
    xor eax, eax
    jmp .scan_next_done
.scan_next_error:
    mov eax, -1
.scan_next_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int db_store_scan_close(statement)
db_store_scan_close:
    test rdi, rdi
    jz .scan_close_error
    jmp sqlite3_finalize
.scan_close_error:
    mov eax, -1
    ret

; Batch entry (48 bytes): path ptr, path len, key ptr, key len, value ptr, value len.
; int db_store_put_batch(handle, entries, count)
; All upserts are atomic. A savepoint allows this operation inside a caller
; transaction; any invalid entry rolls back the entire batch.
db_store_put_batch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor r15d, r15d
    test r12, r12
    jz .batch_error
    test r13, r13
    jz .batch_error
    mov rdi, r12
    lea rsi, [rel batch_savepoint_sql]
    call db_store_exec
    test eax, eax
    jnz .batch_error
.batch_loop:
    cmp r15, r14
    jae .batch_commit
    mov rax, r15
    imul rax, 48
    lea rbx, [r13 + rax]
    mov rdi, r12
    mov rsi, [rbx]
    mov rdx, [rbx + 8]
    mov rcx, [rbx + 16]
    mov r8, [rbx + 24]
    mov r9, [rbx + 32]
    mov rax, [rbx + 40]
    mov [rsp], rax
    call db_store_put
    test eax, eax
    jnz .batch_rollback
    inc r15
    jmp .batch_loop
.batch_commit:
    mov rdi, r12
    lea rsi, [rel batch_release_sql]
    call db_store_exec
    test eax, eax
    jnz .batch_rollback
    xor eax, eax
    jmp .batch_done
.batch_rollback:
    mov rdi, r12
    lea rsi, [rel batch_rollback_sql]
    call db_store_exec
    mov rdi, r12
    lea rsi, [rel batch_release_sql]
    call db_store_exec
.batch_error:
    mov eax, -1
.batch_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int db_store_scan_tree_open(handle,prefix,prefix_len,statement_out)
; Opens an ordered cursor over all values in the exact bucket and descendants.
db_store_scan_tree_open:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov qword [rsp], 0
    test r12, r12
    jz .tree_open_error
    test r13, r13
    jz .tree_open_error
    test r15, r15
    jz .tree_open_error
    mov rdi, r12
    lea rsi, [rel scan_tree_sql]
    mov edx, -1
    mov rcx, rsp
    xor r8d, r8d
    call sqlite3_prepare_v2
    test eax, eax
    jnz .tree_open_error
    mov rdi, [rsp]
    mov esi, 1
    mov rdx, r14
    call sqlite3_bind_int64
    test eax, eax
    jnz .tree_open_finalize_error
    mov rdi, [rsp]
    mov esi, 2
    mov rdx, r13
    mov rcx, r14
    mov r8, SQLITE_TRANSIENT
    call sqlite3_bind_blob
    test eax, eax
    jnz .tree_open_finalize_error
    mov rax, [rsp]
    mov [r15], rax
    xor eax, eax
    jmp .tree_open_done
.tree_open_finalize_error:
    mov rdi, [rsp]
    call sqlite3_finalize
.tree_open_error:
    mov eax, -1
.tree_open_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Scan output descriptor (72 bytes):
; +0 path buffer, +8 path capacity, +16 path length output pointer
; +24 key buffer, +32 key capacity, +40 key length output pointer
; +48 value buffer, +56 value capacity, +64 value length output pointer.
; int db_store_scan_tree_next(statement, descriptor)
; Returns 1 row, 0 end, -1 error/capacity failure.
db_store_scan_tree_next:
    cld
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .tree_next_error
    test r13, r13
    jz .tree_next_error
    cmp qword [r13 + 16], 0
    je .tree_next_error
    cmp qword [r13 + 40], 0
    je .tree_next_error
    cmp qword [r13 + 64], 0
    je .tree_next_error
    mov rdi, r12
    call sqlite3_step
    cmp eax, SQLITE_ROW
    je .tree_next_row
    cmp eax, SQLITE_DONE
    je .tree_next_end
    jmp .tree_next_error
.tree_next_row:
    mov rdi, r12
    xor esi, esi
    call sqlite3_column_bytes
    mov [rsp], rax
    mov rdi, r12
    mov esi, 1
    call sqlite3_column_bytes
    mov [rsp + 8], rax
    mov rdi, r12
    mov esi, 2
    call sqlite3_column_bytes
    mov [rsp + 16], rax
    mov rax, [rsp]
    cmp rax, [r13 + 8]
    ja .tree_next_error
    mov rax, [rsp + 8]
    cmp rax, [r13 + 32]
    ja .tree_next_error
    mov rax, [rsp + 16]
    cmp rax, [r13 + 56]
    ja .tree_next_error

    ; Copy path.
    mov rcx, [rsp]
    test rcx, rcx
    jz .tree_path_done
    mov rdi, r12
    xor esi, esi
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, [r13]
    test rdi, rdi
    jz .tree_next_error
    mov rcx, [rsp]
    rep movsb
.tree_path_done:
    ; Copy key.
    mov rcx, [rsp + 8]
    test rcx, rcx
    jz .tree_key_done
    mov rdi, r12
    mov esi, 1
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, [r13 + 24]
    test rdi, rdi
    jz .tree_next_error
    mov rcx, [rsp + 8]
    rep movsb
.tree_key_done:
    ; Copy value.
    mov rcx, [rsp + 16]
    test rcx, rcx
    jz .tree_value_done
    mov rdi, r12
    mov esi, 2
    call sqlite3_column_blob
    mov rsi, rax
    mov rdi, [r13 + 48]
    test rdi, rdi
    jz .tree_next_error
    mov rcx, [rsp + 16]
    rep movsb
.tree_value_done:
    mov rax, [r13 + 16]
    mov rcx, [rsp]
    mov [rax], rcx
    mov rax, [r13 + 40]
    mov rcx, [rsp + 8]
    mov [rax], rcx
    mov rax, [r13 + 64]
    mov rcx, [rsp + 16]
    mov [rax], rcx
    mov eax, 1
    jmp .tree_next_done
.tree_next_end:
    xor eax, eax
    jmp .tree_next_done
.tree_next_error:
    mov eax, -1
.tree_next_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
