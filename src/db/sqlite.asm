default rel

global db_store_open
global db_store_close
global db_store_begin
global db_store_commit
global db_store_rollback
global db_store_put
global db_store_get
global db_store_delete

extern sqlite3_open_v2
extern sqlite3_close
extern sqlite3_exec
extern sqlite3_free
extern sqlite3_prepare_v2
extern sqlite3_bind_blob
extern sqlite3_step
extern sqlite3_finalize
extern sqlite3_column_blob
extern sqlite3_column_bytes

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
            db "CREATE TABLE IF NOT EXISTS sequences (path BLOB PRIMARY KEY NOT NULL, value INTEGER NOT NULL) WITHOUT ROWID;", 0
begin_sql: db "BEGIN IMMEDIATE", 0
commit_sql: db "COMMIT", 0
rollback_sql: db "ROLLBACK", 0
put_sql: db "INSERT INTO kv(path,key,value) VALUES(?1,?2,?3) ON CONFLICT(path,key) DO UPDATE SET value=excluded.value", 0
get_sql: db "SELECT value FROM kv WHERE path=?1 AND key=?2", 0
delete_sql: db "DELETE FROM kv WHERE path=?1 AND key=?2", 0

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
