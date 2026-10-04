; ---------------------------------------------------------------------------
; Text: StrBlt
; Windows 1.0x raster fonts (version 0x100).  GDI passes a pointer to the
; FONTINFO (the font file from dfType on): all glyphs share one bitmap strip,
; dfWidthBytes per scan line, reached through dfBitsPointer.  Fixed-pitch
; fonts: glyph i starts at column i*dfPixWidth; proportional fonts
; (dfPixWidth = 0): a table of start columns follows the header.
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

fi_PixWidth     equ 0x14
fi_PixHeight    equ 0x16
fi_FirstChar    equ 0x1d
fi_LastChar     equ 0x1e
fi_DefaultChar  equ 0x1f
fi_BreakChar    equ 0x20
fi_WidthBytes   equ 0x21
fi_BitsPointer  equ 0x2b
fi_CharOffset   equ 0x33

; StrBlt is the exported entry: its "mov ax,ds / nop" is patched to load
; DGROUP.  It adds the ExtTextOut-only parameters and joins the common code.
StrBlt:
        mov     ax, ds
        nop
        mov     [cs:dataseg], ax
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
        PROLOG_INT
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
        ; colours for the destination type
        mov     al, [g_fg]
        mov     ah, [g_bk]
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .cc
        mov     al, [g_fgm]
        mov     ah, [g_bkm]
.cc:    mov     [tx_fg], al
        mov     [tx_bk], ah
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
        mov     al, [tx_bk]
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

; fill_grect: fill g_x,g_y,g_w,g_h of dst with value al (exclusion included)
fill_grect:
        mov     [fill_val], al
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
        mov     [ft_base], si
        mov     ax, [es:si+fi_PixHeight]
        mov     [ft_h], ax
        mov     ax, [es:si+fi_PixWidth]
        mov     [ft_pw], ax
        mov     ax, [es:si+fi_WidthBytes]
        mov     [ft_wb], ax
        mov     ax, [es:si+fi_BitsPointer]
        mov     [ft_boff], ax
        mov     ax, [es:si+fi_BitsPointer+2]
        mov     [ft_bseg], ax
        pop     es
        ret

; text_char: index si (0-based in string) -> ax = advance, cx = glyph width,
;            dx = first column of the glyph in the font strip.
text_char:
        push    bx
        push    es
        push    si
        push    di
        les     bx, [bp+et_lpStr]
        mov     al, [es:bx+si]
        mov     es, [ft_seg]
        mov     di, [ft_base]
        cmp     al, [es:di+fi_LastChar]
        ja      .def
        sub     al, [es:di+fi_FirstChar]
        jae     .ok
.def:   mov     al, [es:di+fi_DefaultChar]
.ok:    movzx   bx, al
        mov     byte [tx_brk], 0
        cmp     al, [es:di+fi_BreakChar]
        jne     .nb
        mov     byte [tx_brk], 1
.nb:    mov     cx, [ft_pw]
        jcxz    .prop
        mov     ax, bx                  ; fixed pitch
        mul     cx
        mov     dx, ax
        jmp     .adv
.prop:  shl     bx, 1
        mov     dx, [es:bx+di+fi_CharOffset]
        mov     cx, [es:bx+di+fi_CharOffset+2]
        sub     cx, dx
.adv:   les     bx, [bp+et_lpWidths]
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
.r:     pop     di
        pop     si
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
        call    text_char               ; ax = adv, cx = width, dx = first column
        push    ax
        ; draw glyph columns into the mask
        mov     di, [tx_cx]
        sub     di, [g_x]               ; mask index of column 0
        push    es
        mov     es, [ft_bseg]
        mov     ax, [tx_r]              ; row address in the strip
        push    dx
        mul     word [ft_wb]
        pop     dx
        add     ax, [ft_boff]
        mov     [tx_rowp], ax
        jcxz    .gd
.col:   cmp     di, 0
        jl      .sk
        cmp     di, [g_w]
        jge     .gd
        mov     bx, dx
        shr     bx, 3
        add     bx, [tx_rowp]
        mov     al, 0x80
        push    cx
        mov     cl, dl
        and     cl, 7
        shr     al, cl
        pop     cx
        test    [es:bx], al
        jz      .sk
        mov     byte [SBUF+di], 1
.sk:    inc     di
        inc     dx
        loop    .col
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
        mov     al, [tx_bk]
        rep     stosb
        pop     es
        pop     cx
.mix:   push    cx
        mov     cx, dx
        xor     di, di
        mov     al, [tx_fg]
.m:     cmp     byte [SBUF+di], 0
        je      .mn
        mov     [DBUF+di], al
.mn:    inc     di
        loop    .m
        pop     cx
        mov     ax, [tx_row]
        mov     si, DBUF
        call    write_row
        ret

