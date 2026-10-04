; Debug output to the QEMU debug console (port 0xE9)
%if DEBUG
dbg_inline:
        push    bp
        mov     bp, sp
        push    ax
        push    si
        mov     si, [bp+2]
.l:     mov     al, [cs:si]
        inc     si
        or      al, al
        jz      .e
        out     0xE9, al
        jmp     .l
.e:     mov     [bp+2], si
        pop     si
        pop     ax
        pop     bp
        ret

dbg_hex:                                ; ax -> 4 hex digits + space
        push    ax
        push    cx
        mov     cx, 4
.l:     rol     ax, 4
        push    ax
        and     al, 15
        add     al, '0'
        cmp     al, '9'
        jbe     .o
        add     al, 7
.o:     out     0xE9, al
        pop     ax
        loop    .l
        mov     al, ' '
        out     0xE9, al
        pop     cx
        pop     ax
        ret
%endif
