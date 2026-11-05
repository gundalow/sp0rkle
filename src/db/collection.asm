; Higher-level keyed collection operations over the opaque SQLite store.
default rel
global db_store_keyed_delete
global db_store_keyed_scan_open

extern db_key_path_append
extern db_store_delete
extern db_store_bucket_exists
extern db_store_bucket_delete
extern db_store_scan_tree_open

section .text
; int db_store_keyed_delete(handle,parent_path,parent_len,key,key_len,
;                           child_path_scratch,child_path_capacity)
; Mirrors keyed collection Del(): remove a nested bucket recursively if the
; key names a bucket; otherwise delete the direct value at parent_path/key.
db_store_keyed_delete:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov rbp, r9
    mov rax, [rsp + 80]         ; seventh argument after saved registers/frame
    mov [rsp], rax
    test r12, r12
    jz .keydel_error
    test r13, r13
    jz .keydel_error
    test r15, r15
    jz .keydel_error
    test rbp, rbp
    jz .keydel_error
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    mov rcx, rbx
    mov r8, rbp
    mov r9, [rsp]
    call db_key_path_append
    test rax, rax
    js .keydel_error
    mov [rsp + 8], rax          ; child path length
    mov rdi, r12
    mov rsi, rbp
    mov rdx, rax
    call db_store_bucket_exists
    cmp eax, 1
    je .keydel_bucket
    test eax, eax
    jnz .keydel_error
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    mov r8, rbx
    call db_store_delete
    jmp .keydel_done
.keydel_bucket:
    mov rdi, r12
    mov rsi, rbp
    mov rdx, [rsp + 8]
    call db_store_bucket_delete
    jmp .keydel_done
.keydel_error:
    mov eax, -1
.keydel_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int db_store_keyed_scan_open(handle,path,path_len,key,key_len,
;                              statement_out,path_scratch,path_capacity)
; A zero-length key scans the given bucket subtree; otherwise scans the
; subtree rooted at path + length-delimited key element.
db_store_keyed_scan_open:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, r8
    mov rbp, r9
    mov rax, [rsp + 80]
    mov [rsp], rax
    mov rax, [rsp + 88]
    mov [rsp + 8], rax
    test r12, r12
    jz .keyscan_error
    test r13, r13
    jz .keyscan_error
    test rbp, rbp
    jz .keyscan_error
    test rbx, rbx
    jnz .keyscan_nested
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, rbp
    call db_store_scan_tree_open
    jmp .keyscan_done
.keyscan_nested:
    test r15, r15
    jz .keyscan_error
    test qword [rsp], 0
    ; For non-empty keys, use caller scratch to build the nested path.
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    mov rcx, rbx
    mov r8, [rsp]
    mov r9, [rsp + 8]
    call db_key_path_append
    test rax, rax
    js .keyscan_error
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, rax
    mov rcx, rbp
    call db_store_scan_tree_open
    jmp .keyscan_done
.keyscan_error:
    mov eax, -1
.keyscan_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
