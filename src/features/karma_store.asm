; SQLite persistence callbacks for the Karma record ABI.
default rel
global karma_sqlite_lookup
global karma_sqlite_put

extern db_key_encode_string
extern db_store_get
extern db_store_put
extern karma_bson_decode
extern karma_bson_encode

section .rodata
karma_path: db "karma"
karma_key_name: db "key"

section .text
; Context (104 bytes):
; +0 SQLite handle
; +8 BSON scratch buffer, +16 capacity
; +24 encoded key scratch, +32 capacity
; +40 subject decode buffer, +48 capacity
; +56 key decode buffer, +64 capacity
; +72 upvoter decode buffer, +80 capacity
; +88 downvoter decode buffer, +96 capacity
;
; int karma_sqlite_lookup(ctx,key,key_len,record_out)
; Returns 1 found, 0 absent, -1 on storage/decoding failure.
karma_sqlite_lookup:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 112
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    test r12, r12
    jz .lookup_error
    test r13, r13
    jz .lookup_error
    test r15, r15
    jz .lookup_error
    mov rbx, [r12]
    test rbx, rbx
    jz .lookup_error

    ; Encode the same final key element used by db.K{db.S{"key", value}}.
    lea rdi, [rel karma_key_name]
    mov esi, 3
    mov rdx, r13
    mov rcx, r14
    mov r8, [r12 + 24]
    mov r9, [r12 + 32]
    call db_key_encode_string
    test rax, rax
    js .lookup_error
    mov r14, rax

    ; db_store_get(handle,path,5,key,key_len,out,capacity,&length)
    mov qword [rsp + 8], 0
    mov qword [rsp], 0
    mov rdi, rbx
    lea rsi, [rel karma_path]
    mov edx, 5
    mov rcx, [r12 + 24]
    mov r8, r14
    mov r9, [r12 + 8]
    mov rax, [r12 + 16]
    mov [rsp], rax
    lea rax, [rsp + 104]
    mov [rsp + 8], rax
    call db_store_get
    cmp eax, 1
    je .lookup_found
    test eax, eax
    jz .lookup_missing
    jmp .lookup_error

.lookup_found:
    ; Build the BSON decoder request in the local frame.
    mov rax, [r12 + 8]
    mov [rsp + 16], rax
    mov rax, [rsp + 104]
    mov [rsp + 24], rax
    mov [rsp + 32], r15
    mov rax, [r12 + 40]
    mov [rsp + 40], rax
    mov rax, [r12 + 48]
    mov [rsp + 48], rax
    mov rax, [r12 + 56]
    mov [rsp + 56], rax
    mov rax, [r12 + 64]
    mov [rsp + 64], rax
    mov rax, [r12 + 72]
    mov [rsp + 72], rax
    mov rax, [r12 + 80]
    mov [rsp + 80], rax
    mov rax, [r12 + 88]
    mov [rsp + 88], rax
    mov rax, [r12 + 96]
    mov [rsp + 96], rax
    lea rdi, [rsp + 16]
    call karma_bson_decode
    test eax, eax
    jnz .lookup_error
    mov eax, 1
    jmp .lookup_done

.lookup_missing:
    xor eax, eax
    jmp .lookup_done
.lookup_error:
    mov eax, -1
.lookup_done:
    add rsp, 112
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int karma_sqlite_put(ctx,record)
; Serializes a BSON record and atomically upserts it in the karma collection.
karma_sqlite_put:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .put_error
    test r13, r13
    jz .put_error
    mov rbx, [r12]
    test rbx, rbx
    jz .put_error

    ; The record's normalized key is a NUL-terminated string.
    mov r14, [r13 + 16]
    test r14, r14
    jz .put_error
    mov rax, [r12 + 32]
    cmp rax, 4
    jb .put_error
    sub rax, 4
    xor ecx, ecx
.put_key_length:
    cmp rcx, rax
    jae .put_error
    cmp byte [r14 + rcx], 0
    je .put_key_ready
    inc rcx
    jmp .put_key_length
.put_key_ready:
    mov r15, rcx

    ; Encode "key" + USEP + normalized key.
    lea rdi, [rel karma_key_name]
    mov esi, 3
    mov rdx, r14
    mov rcx, r15
    mov r8, [r12 + 24]
    mov r9, [r12 + 32]
    call db_key_encode_string
    test rax, rax
    js .put_error
    mov r15, rax

    ; Encode BSON into the caller-owned scratch buffer.
    mov rdi, r13
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    lea rcx, [rsp + 8]
    call karma_bson_encode
    test eax, eax
    jnz .put_error

    ; db_store_put(handle,path,5,key,key_len,value,value_len)
    mov rax, [rsp + 8]
    mov [rsp], rax
    mov rdi, rbx
    lea rsi, [rel karma_path]
    mov edx, 5
    mov rcx, [r12 + 24]
    mov r8, r15
    mov r9, [r12 + 8]
    call db_store_put
    jmp .put_done
.put_error:
    mov eax, -1
.put_done:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
