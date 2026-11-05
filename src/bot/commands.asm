default rel

global bot_command_match
global bot_command_normalize_args
global bot_command_dispatch
global bot_is_factoid_addition
global bot_command_help_text
global bot_command_possible

; struct bot_command_entry (32 bytes):
;   +0  const char *prefix
;   +8  uint64_t prefix_len
;   +16 void *handler
;   +24 const char *help
;
; const struct bot_command_entry *bot_command_match(
;   entries, count, text, text_len, size_t *matched_prefix_len)
; Returns the entry with the longest ASCII-case-insensitive prefix match,
; or NULL. Equal-length ties retain the first registered entry.
; Prefixes are byte strings; callers supply explicit lengths.

section .text
bot_command_match:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; entries
    mov r13d, esi               ; count
    mov r14, rdx                ; text
    mov r15, rcx                ; text length
    mov rbx, r8                 ; output matched length
    xor r10d, r10d              ; index
    xor r11d, r11d              ; best length
    xor eax, eax                ; best entry (NULL)

    test rbx, rbx
    jz .scan
    mov qword [rbx], 0

.scan:
    cmp r10d, r13d
    jae .done
    mov r9, r10
    shl r9, 5
    lea r8, [r12 + r9]          ; current entry
    mov rcx, [r8 + 8]           ; prefix length
    test rcx, rcx
    jz .next
    cmp rcx, r15
    ja .next
    cmp rcx, r11
    jbe .next                   ; only strictly longer matches can win

    mov rdi, [r8]               ; prefix
    xor edx, edx
.compare:
    cmp rdx, rcx
    jae .matched
    movzx esi, byte [rdi + rdx]
    movzx r9d, byte [r14 + rdx]
    cmp sil, 'A'
    jb .prefix_ready
    cmp sil, 'Z'
    ja .prefix_ready
    add sil, 32
.prefix_ready:
    cmp r9b, 'A'
    jb .text_ready
    cmp r9b, 'Z'
    ja .text_ready
    add r9b, 32
.text_ready:
    cmp sil, r9b
    jne .next
    inc rdx
    jmp .compare

.matched:
    mov r11, rcx
    mov rax, r8
.next:
    inc r10d
    jmp .scan

.done:
    test rbx, rbx
    jz .return
    mov [rbx], r11
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; ssize_t bot_command_normalize_args(input, input_len, output, output_capacity)
; Trims leading/trailing ASCII whitespace and compresses each internal run
; to one space. Capacity includes the terminating NUL. Returns output length,
; or -1 when output is null/too small. On failure, output[0] is cleared when
; possible. The input and output may not overlap.
bot_command_normalize_args:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    xor ebx, ebx
    xor r10d, r10d
    xor r11d, r11d              ; pending whitespace

    test r14, r14
    jz .error
    test r15, r15
    jz .error

.scan:
    cmp r10, r13
    jae .finish
    movzx eax, byte [r12 + r10]
    inc r10
    cmp al, ' '
    je .space
    cmp al, 9
    jb .character
    cmp al, 13
    jbe .space
.character:
    test r11d, r11d
    jz .write_char
    test rbx, rbx
    jz .clear_pending
    lea rdx, [rbx + 1]
    cmp rdx, r15
    jae .error
    mov byte [r14 + rbx], ' '
    inc rbx
.clear_pending:
    xor r11d, r11d
.write_char:
    lea rdx, [rbx + 1]
    cmp rdx, r15
    jae .error
    mov [r14 + rbx], al
    inc rbx
    jmp .scan
.space:
    test rbx, rbx
    jz .scan
    mov r11d, 1
    jmp .scan
.finish:
    mov byte [r14 + rbx], 0
    mov rax, rbx
    jmp .return
.error:
    test r14, r14
    jz .error_return
    test r15, r15
    jz .error_return
    mov byte [r14], 0
.error_return:
    mov rax, -1
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; int bot_command_dispatch(entries, count, text, text_len, addressed,
;                          factoid_addition, out_args, out_capacity,
;                          out_handler)
; factoid_addition is computed against the original IRC line by the caller.
; Returns 1 when dispatched, 0 when ignored/no matching command, -1 on
; output-buffer error. out_handler receives the opaque handler pointer.
; Output args are the matched suffix with ASCII whitespace normalized.
; Filters are intentionally applied by the caller before this routine.
bot_command_dispatch:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24

    mov r12, rdi                ; entries
    mov r13d, esi               ; count
    mov r14, rdx                ; original text
    mov r15, rcx                ; text length
    mov ebx, r8d                ; addressed
    mov r10d, r9d               ; factoid-addition flag
    mov r11, [rbp + 16]         ; out_args
    mov rax, [rbp + 24]         ; out_capacity
    mov [rbp - 48], rax
    mov rax, [rbp + 32]         ; out_handler
    mov [rbp - 56], rax

    test r11, r11
    jz .invalid
    cmp qword [rbp - 48], 0
    je .invalid
    mov byte [r11], 0
    mov rax, [rbp - 56]
    test rax, rax
    jz .invalid
    mov qword [rax], 0

    test r10d, r10d
    jnz .not_dispatched

.addressed:
    test ebx, ebx
    jz .not_dispatched
    mov rdi, r12
    mov esi, r13d
    mov rdx, r14
    mov rcx, r15
    xor r8d, r8d
    call bot_command_match
    test rax, rax
    jz .not_dispatched

    mov rdx, [rax + 16]         ; handler
    test rdx, rdx
    jz .not_dispatched
    mov r8, [rbp - 56]
    mov [r8], rdx

    ; Preserve selected entry's prefix length before the call in r9.
    mov r9, [rax + 8]
    mov rdi, r14
    add rdi, r9
    mov rsi, r15
    sub rsi, r9
    mov rdx, [rbp + 16]
    mov rcx, [rbp - 48]
    call bot_command_normalize_args
    test rax, rax
    js .buffer_error
    mov eax, 1
    jmp .done

.not_dispatched:
    xor eax, eax
    jmp .done
.buffer_error:
    mov r8, [rbp - 56]
    mov qword [r8], 0
    mov eax, -1
    jmp .done
.invalid:
    mov eax, -1
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; int bot_is_factoid_addition(text, text_len)
; Mirrors util.IsFactoidAddition: case-insensitive substring search for
; either ":is" or ":=". Operates on explicit-length bytes.
bot_is_factoid_addition:
    xor r8d, r8d
.scan_fact:
    lea rax, [r8 + 3]
    cmp rax, rsi
    ja .check_equal
    cmp byte [rdi + r8], ':'
    jne .check_equal
    movzx eax, byte [rdi + r8 + 1]
    or al, 32
    cmp al, 'i'
    jne .check_equal
    movzx eax, byte [rdi + r8 + 2]
    or al, 32
    cmp al, 's'
    je .fact_yes
.check_equal:
    lea rax, [r8 + 2]
    cmp rax, rsi
    ja .advance
    cmp byte [rdi + r8], ':'
    jne .advance
    cmp byte [rdi + r8 + 1], '='
    je .fact_yes
.advance:
    inc r8
    cmp r8, rsi
    jb .scan_fact
    xor eax, eax
    ret
.fact_yes:
    mov eax, 1
    ret


; const char *bot_command_help_text(entries, count, text, text_len)
; Returns the help string associated with the longest matching prefix,
; or NULL if no command prefix matches.
bot_command_help_text:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov rbx, rcx
    mov rdi, r12
    mov esi, r13d
    mov rdx, r14
    mov rcx, rbx
    xor r8d, r8d
    call bot_command_match
    test rax, rax
    jz .no_help
    mov rax, [rax + 24]
    jmp .help_return
.no_help:
    xor eax, eax
.help_return:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ssize_t bot_command_possible(entries, count, text, text_len, out, capacity)
; Finds prefixes containing any ASCII-whitespace-delimited input word,
; case-insensitively. Results are prefix pointers in registration order,
; limited to min(capacity, 10). Returns count, or -1 for invalid output.
; This mirrors commandSet.possible; Unicode whitespace/case folding are
; intentionally outside this byte-oriented ABI.
bot_command_possible:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 104

    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15, rcx
    mov [rbp - 48], r9       ; output capacity
    mov [rbp - 56], r8       ; output array
    mov qword [rbp - 64], 0  ; entry index
    mov qword [rbp - 72], 0  ; result count
    mov qword [rbp - 144], 0 ; text cursor

    test r9, r9
    jz .possible_empty
    test r8, r8
    jz .possible_error

.entry_loop:
    mov rax, [rbp - 72]
    cmp rax, 10
    jae .possible_done
    cmp rax, [rbp - 48]
    jae .possible_done
    mov eax, [rbp - 64]
    cmp eax, r13d
    jae .possible_done
    mov rax, [rbp - 64]
    shl rax, 5
    lea rdx, [r12 + rax]
    mov [rbp - 80], rdx
    mov rax, [rdx]
    mov [rbp - 88], rax
    mov rax, [rdx + 8]
    mov [rbp - 96], rax
    test rax, rax
    jz .next_entry
    mov qword [rbp - 144], 0 ; restart input scan for each prefix

.word_loop:
    mov rax, [rbp - 144]
.skip_word_space:
    cmp rax, r15
    jae .next_entry
    movzx edx, byte [r14 + rax]
    cmp dl, ' '
    je .skip_one_space
    cmp dl, 9
    jb .word_start
    cmp dl, 13
    jbe .skip_one_space
    jmp .word_start
.skip_one_space:
    inc rax
    jmp .skip_word_space
.word_start:
    mov [rbp - 104], rax
.word_end:
    cmp rax, r15
    jae .word_ready
    movzx edx, byte [r14 + rax]
    cmp dl, ' '
    je .word_ready
    cmp dl, 9
    jb .word_continue
    cmp dl, 13
    jbe .word_ready
.word_continue:
    inc rax
    jmp .word_end
.word_ready:
    mov [rbp - 144], rax
    mov rdx, rax
    sub rdx, [rbp - 104]
    mov [rbp - 112], rdx
    test rdx, rdx
    jz .next_entry
    cmp rdx, [rbp - 96]
    ja .word_loop

    mov qword [rbp - 120], 0 ; prefix substring offset
.substring_loop:
    mov rax, [rbp - 120]
    mov rdx, [rbp - 96]
    sub rdx, [rbp - 112]
    cmp rax, rdx
    ja .word_loop
    mov qword [rbp - 136], 0 ; character index
.compare_word:
    mov rcx, [rbp - 136]
    cmp rcx, [rbp - 112]
    jae .found_possible
    mov rax, [rbp - 104]
    add rax, rcx
    movzx eax, byte [r14 + rax]
    cmp al, 'A'
    jb .text_folded
    cmp al, 'Z'
    ja .text_folded
    add al, 32
.text_folded:
    mov rdx, [rbp - 120]
    add rdx, rcx
    mov rcx, [rbp - 88]
    movzx edx, byte [rcx + rdx]
    cmp dl, 'A'
    jb .prefix_folded
    cmp dl, 'Z'
    ja .prefix_folded
    add dl, 32
.prefix_folded:
    cmp al, dl
    jne .try_next_substring
    inc qword [rbp - 136]
    jmp .compare_word
.try_next_substring:
    inc qword [rbp - 120]
    jmp .substring_loop

.found_possible:
    mov rax, [rbp - 72]
    mov rcx, [rbp - 56]
    mov rdx, [rbp - 88]
    mov [rcx + rax*8], rdx
    inc qword [rbp - 72]
    jmp .next_entry

.next_entry:
    inc qword [rbp - 64]
    jmp .entry_loop

.possible_empty:
    xor eax, eax
    jmp .possible_return
.possible_done:
    mov rax, [rbp - 72]
    jmp .possible_return
.possible_error:
    mov rax, -1
.possible_return:
    add rsp, 104
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
