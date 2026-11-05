; Higher-level keyed collection operations over the opaque SQLite store.
default rel
global db_store_keyed_delete
global db_store_keyed_scan_open
global db_store_indexed_get
global db_store_indexed_scan_next

extern db_key_path_append
extern db_store_delete
extern db_store_bucket_exists
extern db_store_bucket_delete
extern db_store_scan_tree_open
extern db_store_scan_tree_next
extern db_store_get

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

; Indexed get request (104 bytes):
; +0 values path ptr, +8 values path_len,
; +16 indexes path ptr, +24 indexes path_len,
; +32 index path ptr, +40 index path_len,
; +48 index key ptr, +56 index key_len,
; +64 pointer scratch, +72 pointer capacity,
; +80 BSON output, +88 output capacity, +96 output length pointer.
; int db_store_indexed_get(handle, request)
; Resolves an index key to its _id pointer when needed, then fetches the
; canonical BSON value from the values path. Returns 1 found, 0 absent, -1 error.
db_store_indexed_get:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .idxget_error
    test r13, r13
    jz .idxget_error
    mov r14, [r13 + 48]
    mov r15, [r13 + 56]
    test r14, r14
    jz .idxget_error
    ; A direct _id key bypasses index traversal only at the index root.
    cmp qword [r13 + 40], 0
    jne .idxget_resolve
    cmp r15, 4
    jb .idxget_resolve
    cmp byte [r14], '_'
    jne .idxget_resolve
    cmp byte [r14 + 1], 'i'
    jne .idxget_resolve
    cmp byte [r14 + 2], 'd'
    jne .idxget_resolve
    cmp byte [r14 + 3], 0x1f
    jne .idxget_resolve
    mov rbx, r14
    mov r15, [r13 + 56]
    jmp .idxget_value

.idxget_resolve:
    ; Fetch the pointer stored at indexes_path/index_path/index_key.
    cmp qword [r13 + 32], 0
    je .idxget_error
    cmp qword [r13 + 64], 0
    je .idxget_error
    mov qword [rsp + 16], 0
    mov rdi, r12
    mov rsi, [r13 + 32]
    mov rdx, [r13 + 40]
    mov rcx, [r13 + 48]
    mov r8, [r13 + 56]
    mov r9, [r13 + 64]
    mov rax, [r13 + 72]
    mov [rsp], rax
    lea rax, [rsp + 16]
    mov [rsp + 8], rax
    call db_store_get
    cmp eax, 1
    je .idxget_pointer_found
    test eax, eax
    jz .idxget_missing
    jmp .idxget_error
.idxget_pointer_found:
    mov rbx, [r13 + 64]
    mov r15, [rsp + 16]
    test r15, r15
    jz .idxget_error

.idxget_value:
    ; Fetch canonical record using the resolved _id pointer.
    mov rdi, r12
    mov rsi, [r13]
    mov rdx, [r13 + 8]
    mov rcx, rbx
    mov r8, r15
    mov r9, [r13 + 80]
    mov rax, [r13 + 88]
    mov [rsp], rax
    mov rax, [r13 + 96]
    mov [rsp + 8], rax
    call db_store_get
    jmp .idxget_done
.idxget_missing:
    xor eax, eax
    jmp .idxget_done
.idxget_error:
    mov eax, -1
.idxget_done:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Indexed scan request (80 bytes):
; +0 SQLite statement, +8 scan-tree descriptor,
; +16 canonical values path, +24 path_len,
; +32 BSON output, +40 capacity, +48 output length pointer,
; +56 seen ObjectId array (16-byte entries, optional),
; +64 seen count pointer (optional), +72 seen capacity in entries.
; int db_store_indexed_scan_next(handle, request)
; Returns one unique canonical BSON record, skips duplicate/stale pointers.
db_store_indexed_scan_next:
    cld
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rdi
    mov r13, rsi
    test r12, r12
    jz .idxscan_error
    test r13, r13
    jz .idxscan_error
    mov r14, [r13 + 8]
    test r14, r14
    jz .idxscan_error
    mov r15, [r13 + 56]
    mov rbx, [r13 + 64]
    mov rbp, [r13 + 72]
    cmp qword [r13 + 48], 0
    je .idxscan_error
.idxscan_loop:
    mov rdi, [r13]
    mov rsi, r14
    call db_store_scan_tree_next
    cmp eax, 1
    je .idxscan_row
    test eax, eax
    jz .idxscan_end
    jmp .idxscan_error
.idxscan_row:
    mov rax, [r14 + 64]
    test rax, rax
    jz .idxscan_error
    mov rcx, [rax]
    cmp rcx, 16
    jne .idxscan_loop
    mov r10, [r14 + 48]         ; ObjectId pointer bytes from index value
    test r10, r10
    jz .idxscan_error

    ; Optional deduplication by 12-byte ObjectId pointer.
    test rbx, rbx
    jz .idxscan_fetch
    test r15, r15
    jz .idxscan_error
    mov r11, [rbx]
    cmp r11, rbp
    ja .idxscan_error
    xor r9d, r9d
.idxscan_seen_loop:
    cmp r9, r11
    jae .idxscan_not_seen
    mov rax, r9
    shl rax, 4
    lea rdx, [r15 + rax]
    xor ecx, ecx
.idxscan_compare:
    cmp ecx, 16
    jae .idxscan_duplicate
    mov al, [rdx + rcx]
    cmp al, [r10 + rcx]
    jne .idxscan_next_seen
    inc ecx
    jmp .idxscan_compare
.idxscan_next_seen:
    inc r9
    jmp .idxscan_seen_loop
.idxscan_duplicate:
    jmp .idxscan_loop
.idxscan_not_seen:
    cmp r11, rbp
    jae .idxscan_error

.idxscan_fetch:
    ; Resolve pointer into the canonical values bucket.
    mov rdi, r12
    mov rsi, [r13 + 16]
    mov rdx, [r13 + 24]
    mov rcx, r10
    mov r8d, 16
    mov r9, [r13 + 32]
    mov rax, [r13 + 40]
    mov [rsp], rax
    mov rax, [r13 + 48]
    mov [rsp + 8], rax
    call db_store_get
    cmp eax, 1
    je .idxscan_found
    test eax, eax
    jz .idxscan_loop             ; stale index pointer; continue scanning
    jmp .idxscan_error

.idxscan_found:
    mov r10, [r14 + 48]
    test rbx, rbx
    jz .idxscan_return_row
    mov rax, [rbx]
    shl rax, 4
    lea rdi, [r15 + rax]
    mov rsi, r10
    mov ecx, 16
    rep movsb
    inc qword [rbx]
.idxscan_return_row:
    mov eax, 1
    jmp .idxscan_done
.idxscan_end:
    xor eax, eax
    jmp .idxscan_done
.idxscan_error:
    mov eax, -1
.idxscan_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
