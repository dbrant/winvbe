; ---------------------------------------------------------------------------
; Pixel and ScanLR
; ---------------------------------------------------------------------------

; Pixel(lpDestDev, x, y, PhysColor, lpDrawMode)
px_lpDst        equ 18
px_x            equ 16
px_y            equ 14
px_color        equ 10
px_lpDM         equ 6

Pixel:
        PROLOG
        DBG     'Pixel '
        DBGX    [bp+px_x]
        DBGX    [bp+px_y]
        DBGX    [bp+px_color]
        DBGX    [bp+px_lpDM+2]
        DBG     13,10
        les     si, [bp+px_lpDst]
        mov     bx, dst
        call    load_surf
        mov     cx, [bp+px_x]
        cmp     cx, [dst+SURF.width]
        jae     .oob
        mov     ax, [bp+px_y]
        cmp     ax, [dst+SURF.height]
        jae     .oob
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        push    ax
        push    cx
        mov     bx, ax                  ; y0
        mov     ax, cx                  ; x0
        inc     cx                      ; x1
        mov     dx, bx
        inc     dx                      ; y1
        call    excl_begin
        mov     byte [g_excl], 1
        pop     cx
        pop     ax
.ne:    les     si, [bp+px_lpDM]
        mov     dx, es
        or      dx, si
        jnz     .set
        ; get
        mov     bx, dst
        call    get_pixel
        and     eax, PIXMASK
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .gc
        and     eax, 1                  ; mono: black or white
        mov     edx, eax
        neg     eax
        and     eax, PIXMASK
        jmp     .gm
.gc:    push    eax
        call    elem_mono
        movzx   edx, al
        pop     eax
.gm:    shl     edx, MONOB*8
        or      eax, edx
%if PALMGR
        or      eax, 0xFF000000
%endif
        push    eax
        call    blt_unexclude
        pop     ax
        pop     dx
        jmp     .done
.set:   push    ax
        push    cx
        call    get_dm_colors
        mov     ax, [g_rop2]
        call    rop2_to_rop3
%if BITROP
        call    build_rop_table
        mov     eax, [bp+px_color]
        call    phys_value
        mov     [ln_fgval], eax
        pop     cx
        pop     ax
        mov     bx, dst
        push    ax
        call    get_pixel
        mov     edx, eax
        mov     eax, [ln_fgval]
        call    rop_px
        mov     edx, eax
        pop     ax
%else
        mov     dl, [bp+px_color]
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .sc
        mov     dl, [bp+px_color+1]
.sc:    call    make_pen_table
        pop     cx
        pop     ax
        mov     bx, dst
        push    ax
        call    get_pixel
        and     al, CMASK
        mov     bx, pentab
        xlatb
        mov     dl, al
        pop     ax
%endif
        mov     bx, dst
        call    put_pixel
        call    blt_unexclude
        xor     ax, ax
        xor     dx, dx
        jmp     .done
.oob:   xor     ax, ax
        mov     dx, 0x8000
.done:  EPILOG  16

; ScanLR(lpDestDev, x, y, PhysColor, Style)
sl_lpDst        equ 16
sl_x            equ 14
sl_y            equ 12
sl_color        equ 8
sl_style        equ 6

ScanLR:
        PROLOG
        les     si, [bp+sl_lpDst]
        mov     bx, dst
        call    load_surf
        mov     cx, [bp+sl_x]
        cmp     cx, [dst+SURF.width]
        jae     .oob
        mov     ax, [bp+sl_y]
        cmp     ax, [dst+SURF.height]
        jae     .oob
        push    ax
%if PALMGR
        mov     byte [g_xlat], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .c
        mov     al, [pal_mod]
        mov     [g_xlat], al
.c:
%endif
        mov     eax, [bp+sl_color]
        call    phys_value
        mov     [sl_target], eax
        pop     ax
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        push    ax
        mov     bx, ax
        xor     ax, ax
        mov     cx, XRES
        mov     dx, bx
        inc     dx
        call    excl_begin
        mov     byte [g_excl], 1
        pop     ax
.ne:    ; scan the row in chunks of at most MAXW pixels
        mov     bx, dst
        test    word [bp+sl_style], 2
        jnz     .left
        mov     cx, [bp+sl_x]           ; chunk start
.rc:    mov     dx, [dst+SURF.width]
        sub     dx, cx
        jle     .nf
        cmp     dx, MAXW
        jbe     .rc1
        mov     dx, MAXW
.rc1:   mov     ax, [bp+sl_y]
        mov     di, DBUF
        call    read_row
        mov     si, DBUF
        push    cx
        push    dx
        mov     bx, cx                  ; current x
.rl:    call    .test
        jc      .rfound
        add     si, ELEM
        inc     bx
        dec     dx
        jnz     .rl
        pop     dx
        pop     cx
        add     cx, dx
        mov     bx, dst
        jmp     .rc
.rfound:
        pop     dx
        pop     cx
        jmp     .found
.left:  mov     cx, [bp+sl_x]
        inc     cx                      ; chunk end (exclusive)
.lc:    or      cx, cx
        jle     .nf
        mov     dx, cx
        cmp     dx, MAXW
        jbe     .lc1
        mov     dx, MAXW
.lc1:   push    cx
        sub     cx, dx                  ; chunk start
        mov     ax, [bp+sl_y]
        mov     di, DBUF
        mov     bx, dst
        call    read_row
        mov     si, dx
        dec     si                      ; last pixel of chunk
        shl     si, ESHIFT
        add     si, DBUF
        pop     bx
        dec     bx                      ; its x
        push    cx
.ll:    call    .test
        jc      .lfound
        sub     si, ELEM
        dec     bx
        dec     dx
        jnz     .ll
        pop     cx                      ; next chunk ends where this one started
        jmp     .lc
.lfound:
        pop     cx
        jmp     .found
.nf:    mov     ax, -1
        jmp     .fin
.found: mov     ax, bx
.fin:   push    ax
        call    blt_unexclude
        pop     ax
        jmp     .done
.oob:   mov     ax, 0x8000
.done:  DBG     'ScanLR '
        DBGX    [bp+sl_x]
        DBGX    [bp+sl_y]
        DBGX    [bp+sl_color]
        DBGX    [bp+sl_style]
        DBG     '-> '
        DBGX    ax
        push    ax
        movzx   ax, byte [dst+SURF.kind]
        DBGX    ax
        pop     ax
        DBG     13,10
        EPILOG  14
; .test: CF=1 if pixel at [si] satisfies the search
.test:  mov     EA, [si]
%if BPP = 32
        and     eax, PIXMASK
%elif BPP = 4
        and     al, CMASK
%endif
        cmp     EA, [sl_target]
        je      .eq
        ; pixel differs: matches when searching for "not colour" (bit 0 set)
        test    byte [bp+sl_style], 1
        jz      .no
        stc
        ret
.eq:    test    byte [bp+sl_style], 1
        jnz     .no
        stc
        ret
.no:    clc
        ret
