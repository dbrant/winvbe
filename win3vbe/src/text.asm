; ---------------------------------------------------------------------------
; Text: StrBlt / ExtTextOut / GetCharWidth
; Windows 2.x raster fonts (version 0x200): char table at 0x76, entries are
; (width, offset); glyphs stored by byte columns, dfPixHeight bytes each.
; ---------------------------------------------------------------------------
et_lpDst        equ 0x2a
et_x            equ 0x28
et_y            equ 0x26
et_lpClip       equ 0x22
et_lpStr        equ 0x1e
et_count        equ 0x1c
et_lpFont       equ 0x18
et_lpDM         equ 0x14
et_lpXF         equ 0x10
et_lpWidths     equ 0x0c
et_lpOpaque     equ 0x08
et_opts         equ 0x06

ETO_OPAQUE      equ 2
ETO_CLIPPED     equ 4

StrBlt:
        pop     cx                      ; return address
        pop     bx
        xor     ax, ax
        push    ax                      ; lpCharWidths = NULL
        push    ax
        push    ax                      ; lpOpaqueRect = NULL
        push    ax
        push    ax                      ; wOptions = 0
        push    bx
        push    cx
        ; fall through
ExtTextOut:
        PROLOG
        mov     ax, [bp+et_count]
        or      ax, ax
        jns     .draw
        neg     ax
        mov     [tx_count], ax
        call    text_setup_font
        call    text_width
        mov     dx, [ft_h]
        jmp     .ret
.draw:  mov     [tx_count], ax
        les     si, [bp+et_lpDst]
        mov     bx, dst
        call    load_surf
        les     si, [bp+et_lpDM]
        call    get_dm_colors
        les     si, [bp+et_lpClip]
        call    set_clip
        call    text_setup_font
        ; colors for the destination type
        mov     eax, [g_fg]
        mov     edx, [g_bk]
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .cc
        movzx   eax, byte [g_fgm]
        movzx   edx, byte [g_bkm]
.cc:    mov     [tx_fg], eax
        mov     [tx_bk], edx
        ; opaque rectangle
        test    word [bp+et_opts], ETO_OPAQUE
        jz      .noopq
        les     si, [bp+et_lpOpaque]
        mov     ax, es
        or      ax, si
        jz      .noopq
        mov     ax, [es:si]
        mov     bx, [es:si+2]
        mov     cx, [es:si+4]
        mov     dx, [es:si+6]
        call    clip_rect
        jc      .noopq
        mov     eax, [tx_bk]
        call    fill_grect
.noopq: test    word [bp+et_opts], ETO_CLIPPED
        jz      .nocl
        les     si, [bp+et_lpOpaque]
        mov     ax, es
        or      ax, si
        jz      .nocl
        call    and_clip
.nocl:  cmp     word [tx_count], 0
        je      .ok
        call    text_width              ; ax = width
        mov     cx, [bp+et_x]
        add     cx, ax
        mov     ax, [bp+et_x]
        mov     bx, [bp+et_y]
        mov     dx, bx
        add     dx, [ft_h]
        call    clip_rect
        jc      .ok
        ; exclusion
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        mov     ax, [g_x]
        mov     bx, [g_y]
        mov     cx, ax
        add     cx, [g_w]
        mov     dx, bx
        add     dx, [g_h]
        call    excl_begin
        mov     byte [g_excl], 1
.ne:    mov     ax, [g_x]
        mov     [ch_x], ax
        mov     ax, [g_w]
        mov     [ch_w], ax
        mov     word [ch_off], 0
.tch:   mov     ax, [ch_x]
        add     ax, [ch_off]
        mov     [g_x], ax
        mov     ax, [ch_w]
        sub     ax, [ch_off]
        cmp     ax, MAXW
        jle     .tw
        mov     ax, MAXW
.tw:    mov     [g_w], ax
        mov     ax, [g_y]
        mov     [tx_row], ax
        mov     cx, [g_h]
.rl:    push    cx
        call    text_row
        inc     word [tx_row]
        pop     cx
        loop    .rl
        add     word [ch_off], MAXW
        mov     ax, [ch_off]
        cmp     ax, [ch_w]
        jl      .tch
        call    blt_unexclude
.ok:    xor     ax, ax
        xor     dx, dx
.ret:   EPILOG  0x28

; fill_grect: fill g_x,g_y,g_w,g_h of dst with value eax (exclusion included)
fill_grect:
        mov     [fill_val], eax
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        mov     ax, [g_x]
        mov     bx, [g_y]
        mov     cx, ax
        add     cx, [g_w]
        mov     dx, bx
        add     dx, [g_h]
        call    excl_begin
        mov     byte [g_excl], 1
.ne:    mov     bx, dst
        mov     ax, [g_y]
        mov     cx, [g_x]
        mov     dx, [g_w]
        mov     si, [g_h]
.l:     call    fill_row_val
        inc     ax
        dec     si
        jnz     .l
        call    blt_unexclude
        ret

; and_clip: es:si -> RECT, clip_* &= rect
and_clip:
        mov     ax, [es:si]
        cmp     ax, [clip_x0]
        jle     .a
        mov     [clip_x0], ax
.a:     mov     ax, [es:si+2]
        cmp     ax, [clip_y0]
        jle     .b
        mov     [clip_y0], ax
.b:     mov     ax, [es:si+4]
        cmp     ax, [clip_x1]
        jge     .c
        mov     [clip_x1], ax
.c:     mov     ax, [es:si+6]
        cmp     ax, [clip_y1]
        jge     .r
        mov     [clip_y1], ax
.r:     ret

; text_setup_font: font header values into ft_*
text_setup_font:
        push    es
        les     si, [bp+et_lpFont]
        mov     [ft_seg], es
        mov     ax, [es:0x58]
        mov     [ft_h], ax
        pop     es
        ret

; text_char: index si (0-based in string) -> ax = advance, cx = glyph width,
;            dx = glyph offset.  Uses the ExtTextOut frame.
text_char:
        push    bx
        push    es
        push    si
        les     bx, [bp+et_lpStr]
        mov     al, [es:bx+si]
        mov     es, [ft_seg]
        sub     al, [es:0x5f]
        jb      .def
        mov     bl, [es:0x60]
        sub     bl, [es:0x5f]
        cmp     al, bl
        jbe     .ok
.def:   mov     al, [es:0x61]
.ok:    movzx   bx, al
        mov     [tx_brk], byte 0
        cmp     al, [es:0x62]
        jne     .nb
        mov     [tx_brk], byte 1
.nb:    shl     bx, 2
        mov     cx, [es:bx+0x76]        ; width
        mov     dx, [es:bx+0x78]        ; offset
        ; advance
        les     bx, [bp+et_lpWidths]
        mov     ax, es
        or      ax, bx
        jz      .fw
        shl     si, 1
        mov     ax, [es:bx+si]
        jmp     .r
.fw:    les     bx, [bp+et_lpDM]
        mov     ax, cx
        add     ax, [es:bx+dmCharExtra]
        cmp     byte [tx_brk], 0
        je      .r
        add     ax, [es:bx+dmBreakExtra]
.r:     pop     si
        pop     es
        pop     bx
        ret

; text_width: -> ax = total advance of tx_count characters
text_width:
        push    bx
        push    cx
        push    dx
        push    si
        xor     bx, bx
        xor     si, si
.l:     cmp     si, [tx_count]
        jae     .e
        call    text_char
        add     bx, ax
        inc     si
        jmp     .l
.e:     mov     ax, bx
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret

; text_row: draw row tx_row of the clipped text rectangle
text_row:
        ; clear mask (SBUF) for g_w pixels
        push    es
        push    ds
        pop     es
        mov     di, SBUF
        mov     cx, [g_w]
        xor     al, al
        rep     stosb
        pop     es
        mov     ax, [tx_row]
        sub     ax, [bp+et_y]
        mov     [tx_r], ax              ; glyph row
        mov     ax, [bp+et_x]
        mov     [tx_cx], ax             ; current character x
        xor     si, si
.ch:    cmp     si, [tx_count]
        jae     .comp
        mov     ax, [tx_cx]
        sub     ax, [g_x]
        cmp     ax, [g_w]
        jge     .comp                   ; past the right edge
        call    text_char               ; ax = adv, cx = width, dx = offset
        push    ax
        ; draw glyph columns into the mask
        mov     di, [tx_cx]
        sub     di, [g_x]               ; mask index of column 0
        mov     bx, dx
        add     bx, [tx_r]
        push    es
        mov     es, [ft_seg]
        mov     dl, 0x80
        jcxz    .gd
.col:   cmp     di, 0
        jl      .sk
        cmp     di, [g_w]
        jge     .gd
        test    [es:bx], dl
        jz      .sk
        mov     byte [SBUF+di], 1
.sk:    inc     di
        ror     dl, 1
        jnc     .same
        add     bx, [ft_h]
.same:  loop    .col
.gd:    pop     es
        pop     ax
        add     [tx_cx], ax
        inc     si
        jmp     .ch
.comp:  ; compose destination row

        mov     bx, dst
        mov     ax, [tx_row]
        mov     cx, [g_x]
        mov     dx, [g_w]
        cmp     word [g_bkmode], OPAQUE
        je      .opq
        mov     di, DBUF
        call    read_row
        jmp     .mix
.opq:   push    cx
        push    es
        push    ds
        pop     es
        mov     di, DBUF
        mov     cx, dx
        mov     eax, [tx_bk]
        rep     STOSE
        pop     es
        pop     cx
.mix:   push    cx
        mov     cx, dx
        xor     di, di
        mov     si, DBUF
        mov     eax, [tx_fg]
.m:     cmp     byte [SBUF+di], 0
        je      .mn
        mov     [si], EA
.mn:    inc     di
        add     si, ELEM
        loop    .m
        pop     cx
        mov     ax, [tx_row]
        mov     si, DBUF
        call    write_row
        ret

; GetCharWidth(lpDestDev, lpBuffer, wFirstChar, wLastChar, lpFontInfo,
;              lpDrawMode, lpFontTrans)
GetCharWidth:
        PROLOG
        les     di, [bp+0x16]
        mov     cx, [bp+0x12]
        sub     cx, [bp+0x14]
        jl      .fail
        inc     cx
        mov     si, [bp+0x14]
        push    ds
        mov     ds, [bp+0x10]
.l:     mov     ax, si
        sub     al, [0x5f]
        jb      .def
        mov     bl, [0x60]
        sub     bl, [0x5f]
        cmp     al, bl
        jbe     .ok
.def:   mov     al, [0x61]
.ok:    movzx   bx, al
        shl     bx, 2
        mov     ax, [bx+0x76]
        stosw
        inc     si
        loop    .l
        pop     ds
        mov     ax, 1
        jmp     .r
.fail:  xor     ax, ax
.r:     EPILOG  0x18
