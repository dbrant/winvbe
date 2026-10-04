; ---------------------------------------------------------------------------
; BitBlt, FastBorder and the shared row engine
; ---------------------------------------------------------------------------

; get_dm_colors: es:si -> DRAWMODE (may be NULL).  Needs dst loaded.
; Physical colours: pixel in the low bytes (PIXMASK), mono value in byte MONOB.
get_dm_colors:
        mov     dword [g_bk], WHITE
        mov     byte [g_bkm], 1
        mov     dword [g_fg], 0
        mov     byte [g_fgm], 0
        mov     word [g_bkmode], OPAQUE
        mov     word [g_rop2], 13
        mov     ax, es
        or      ax, si
        jz      .x
        mov     eax, [es:si+dmBkColor]
        and     eax, PIXMASK
        mov     [g_bk], eax
        mov     al, [es:si+dmBkColor+MONOB]
        and     al, 1
        mov     [g_bkm], al
        mov     eax, [es:si+dmTextColor]
        and     eax, PIXMASK
        mov     [g_fg], eax
        mov     al, [es:si+dmTextColor+MONOB]
        and     al, 1
        mov     [g_fgm], al
        mov     ax, [es:si+dmBkMode]
        mov     [g_bkmode], ax
        mov     ax, [es:si+dmRop2]
        mov     [g_rop2], ax
.x:
%if BPP = 8
        ; palette translation applies to colours drawn on the screen
        mov     byte [g_xlat], 0
        cmp     byte [pal_mod], 0
        je      .r
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .r
        mov     byte [g_xlat], 1
        push    bx
        movzx   bx, byte [g_bk]
        mov     bl, [pal_xlat+bx]
        mov     [g_bk], bl
        movzx   bx, byte [g_fg]
        mov     bl, [pal_xlat+bx]
        mov     [g_fg], bl
        pop     bx
%endif
.r:     ret

%if BPP = 8
; xlat_row: si -> elements, cx = count, bx -> 256-byte table.  In place.
xlat_row:
        push    ax
        push    cx
        push    si
        jcxz    .r
.l:     mov     al, [si]
        xlatb
        mov     [si], al
        inc     si
        loop    .l
.r:     pop     si
        pop     cx
        pop     ax
        ret
%endif

; build_prow: es:si -> physical brush.  CF=1 if the brush draws nothing.
; Fills prow[64] (elements) for the destination type, pmask[64] (1 where the
; brush is opaque), g_psolid / g_pval, g_hatch.
build_prow:
        cmp     byte [es:si+BR_STYLE], 1
        jne     .ok
        stc
        ret
.ok:    pushad
        mov     byte [g_hatch], 0
        test    byte [es:si+BR_FLAGS], BRF_HATCH
        jz      .nh
        mov     byte [g_hatch], 1
.nh:    xor     bx, bx                  ; pixel 0..63
.px:    mov     di, bx
        shr     di, 3
        mov     cl, bl
        and     cl, 7
        add     di, si
        mov     al, [es:di+BR_MONO]
        shl     al, cl
        mov     ah, al                  ; bit 7 = mono / hatch bit of the pixel
        mov     di, bx
        shl     di, ESHIFT
        cmp     byte [g_hatch], 0
        jne     .hatch
        mov     byte [pmask+bx], 1
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .col
        shr     ah, 7                   ; mono destination: mono pattern bit
        movzx   eax, ah
        jmp     .st
.col:   push    di
        add     di, si
        mov     EA, [es:di+BR_COLOR]
        pop     di
        jmp     .st
.hatch: shl     ah, 1                   ; CF = hatch bit
        sbb     al, al
        and     al, 1
        mov     [pmask+bx], al
        jz      .hbg
        movzx   eax, byte [es:si+BR_FGMONO]
        cmp     byte [dst+SURF.kind], SK_MONO
        je      .st
        mov     eax, [es:si+BR_FG]
        jmp     .st
.hbg:   movzx   eax, byte [g_bkm]
        cmp     byte [dst+SURF.kind], SK_MONO
        je      .st
        mov     eax, [g_bk]
.st:    mov     [prow+di], EA
        inc     bx
        cmp     bx, 64
        jb      .px
        ; solid?
        mov     byte [g_psolid], 0
        movzx   eax, byte [es:si+BR_FGMONO]
        cmp     byte [dst+SURF.kind], SK_MONO
        je      .sv
        mov     eax, [es:si+BR_FG]
        and     eax, PIXMASK
.sv:    mov     [g_pval], eax
        test    byte [es:si+BR_FLAGS], BRF_SOLID
        jz      .xl
        mov     byte [g_psolid], 1
.xl:
%if BPP = 8
        cmp     byte [g_xlat], 0        ; brush colours drawn on the screen
        je      .done
        cmp     byte [g_hatch], 0
        jne     .xh                     ; (the hatch background is g_bk already)
        mov     si, prow
        mov     cx, 64
        mov     bx, pal_xlat
        call    xlat_row
        jmp     .xs
.xh:    xor     bx, bx                  ; hatch: translate the foreground only
.xhl:   cmp     byte [pmask+bx], 0
        je      .xhn
        movzx   di, byte [prow+bx]
        mov     al, [pal_xlat+di]
        mov     [prow+bx], al
.xhn:   inc     bx
        cmp     bx, 64
        jb      .xhl
.xs:    movzx   bx, byte [g_pval]
        mov     al, [pal_xlat+bx]
        mov     [g_pval], al
.done:
%endif
        popad
        clc
        ret

; solid_prow: eax = value -> prow filled, g_psolid = 1
solid_prow:
        push    eax
        push    cx
        push    di
        push    es
        push    ds
        pop     es
        and     eax, PIXMASK
        mov     [g_pval], eax
        mov     di, prow
        mov     cx, 64
        rep     STOSE
        mov     di, pmask
        mov     cx, 64
        mov     al, 1
        rep     stosb
        mov     byte [g_psolid], 1
        mov     byte [g_hatch], 0
        pop     es
        pop     di
        pop     cx
        pop     eax
        ret

; fill_pb: ax = y.  PBUF[i] = prow[(y&7)*8 + ((g_x+i)&7)] for i < g_w
fill_pb:
        pushad
        and     ax, 7
        shl     ax, 3+ESHIFT
        mov     si, prow
        add     si, ax
        mov     dx, [g_x]
        mov     di, PBUF
        mov     cx, [g_w]
.l:     mov     bx, dx
        and     bx, 7
%if ESHIFT
        shl     bx, ESHIFT
%endif
        mov     EA, [si+bx]
        mov     [di], EA
        add     di, ELEM
        inc     dx
        loop    .l
        popad
        ret

; convert_sb: apply mono<->colour conversion to SBUF[0..g_w)
convert_sb:
        mov     al, [g_conv]
        or      al, al
        jz      .r
        pushad
        mov     si, SBUF
        mov     cx, [g_w]
        cmp     al, 1
        jne     .c2
        mov     edx, [g_bk]             ; mono 1 -> background, 0 -> text colour
        mov     ebx, [g_fg]
.l1:    mov     eax, ebx
        cmp     ESZ [si], 0
        je      .s1
        mov     eax, edx
.s1:    mov     [si], EA
        add     si, ELEM
        loop    .l1
        jmp     .e
.c2:    mov     edx, [g_bk]             ; colour == background -> 1, else 0
.l2:    xor     eax, eax
        cmp     [si], ED
        jne     .s2
        inc     eax
.s2:    mov     [si], EA
        add     si, ELEM
        loop    .l2
.e:     popad
.r:     ret

; clip_blt: clip g_x/g_y/g_w/g_h (and g_sx/g_sy) to dst (and src).  CF=1 if empty.
clip_blt:
        mov     ax, [g_x]
        or      ax, ax
        jns     .1
        sub     [g_sx], ax
        add     [g_w], ax
        mov     word [g_x], 0
.1:     mov     ax, [g_y]
        or      ax, ax
        jns     .2
        sub     [g_sy], ax
        add     [g_h], ax
        mov     word [g_y], 0
.2:     mov     ax, [g_x]
        add     ax, [g_w]
        sub     ax, [dst+SURF.width]
        jle     .3
        sub     [g_w], ax
.3:     mov     ax, [g_y]
        add     ax, [g_h]
        sub     ax, [dst+SURF.height]
        jle     .4
        sub     [g_h], ax
.4:     test    byte [g_ropf], ROPF_S
        jz      .chk
        mov     ax, [g_sx]
        or      ax, ax
        jns     .5
        sub     [g_x], ax
        add     [g_w], ax
        mov     word [g_sx], 0
.5:     mov     ax, [g_sy]
        or      ax, ax
        jns     .6
        sub     [g_y], ax
        add     [g_h], ax
        mov     word [g_sy], 0
.6:     mov     ax, [g_sx]
        add     ax, [g_w]
        sub     ax, [src+SURF.width]
        jle     .7
        sub     [g_w], ax
.7:     mov     ax, [g_sy]
        add     ax, [g_h]
        sub     ax, [src+SURF.height]
        jle     .chk
        sub     [g_h], ax
.chk:   cmp     word [g_w], 0
        jle     .empty
        cmp     word [g_h], 0
        jle     .empty
        clc
        ret
.empty: stc
        ret

; blt_exclude / blt_unexclude: cursor handling for the current g_ rectangle(s)
blt_exclude:
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .s
        mov     ax, [g_x]
        mov     bx, [g_y]
        mov     cx, ax
        add     cx, [g_w]
        mov     dx, bx
        add     dx, [g_h]
        call    excl_begin
        mov     byte [g_excl], 1
.s:     test    byte [g_ropf], ROPF_S
        jz      .r
        cmp     byte [src+SURF.kind], SK_SCREEN
        jne     .r
        mov     ax, [g_sx]
        mov     bx, [g_sy]
        mov     cx, ax
        add     cx, [g_w]
        mov     dx, bx
        add     dx, [g_h]
        call    excl_begin
        mov     byte [g_excl], 1
.r:     ret

blt_unexclude:
        cmp     byte [g_excl], 0
        je      .r
        call    excl_end
        mov     byte [g_excl], 0
.r:     ret

; ---------------------------------------------------------------------------
; blt_rows: perform the operation described by g_* over the clipped rectangle
; ---------------------------------------------------------------------------
blt_rows:
        cmp     word [g_w], MAXW
        jg      .chunk
        jmp     blt_rows1
.chunk: mov     ax, [g_x]
        mov     [ch_x], ax
        mov     ax, [g_sx]
        mov     [ch_sx], ax
        mov     ax, [g_w]
        mov     [ch_w], ax
        ; same surface with the destination right of the source: go right to left
        test    byte [g_ropf], ROPF_S
        jz      .ltr
        call    same_surf
        jne     .ltr
        mov     ax, [g_sx]
        cmp     ax, [g_x]
        jge     .ltr
        mov     ax, [ch_w]
.rtl:   mov     cx, MAXW
        sub     ax, cx
        jge     .r1
        add     cx, ax
        xor     ax, ax
.r1:    push    ax
        call    .do
        pop     ax
        or      ax, ax
        jnz     .rtl
        jmp     .rest
.ltr:   xor     ax, ax
.l1:    mov     cx, [ch_w]
        sub     cx, ax
        cmp     cx, MAXW
        jle     .l2
        mov     cx, MAXW
.l2:    push    ax
        push    cx
        call    .do
        pop     cx
        pop     ax
        add     ax, cx
        cmp     ax, [ch_w]
        jl      .l1
.rest:  mov     ax, [ch_x]
        mov     [g_x], ax
        mov     ax, [ch_sx]
        mov     [g_sx], ax
        mov     ax, [ch_w]
        mov     [g_w], ax
        ret
.do:    mov     dx, [ch_x]
        add     dx, ax
        mov     [g_x], dx
        mov     dx, [ch_sx]
        add     dx, ax
        mov     [g_sx], dx
        mov     [g_w], cx
        call    blt_rows1
        ret

blt_rows1:
        mov     al, [g_rop]
        ; fast solid fills on the screen
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .gen
        xor     edx, edx
        cmp     al, 0x00
        je      .fill
        mov     edx, WHITE
        cmp     al, 0xFF
        je      .fill
        cmp     al, 0xF0
        jne     .gen
        cmp     byte [g_psolid], 0
        je      .gen
        mov     edx, [g_pval]
.fill:  mov     [fill_val], edx
        mov     bx, dst
        mov     ax, [g_y]
        mov     cx, [g_x]
        mov     dx, [g_w]
        mov     si, [g_h]
.fl:    call    fill_row_val
        inc     ax
        dec     si
        jnz     .fl
        ret

.gen:   mov     al, [g_rop]
        cmp     al, 0xCC
        je      .nt
        cmp     al, 0xF0
        je      .nt
        call    build_rop_table
.nt:    ; direction
        mov     word [g_dir], 1
        mov     word [g_row], 0
        test    byte [g_ropf], ROPF_S
        jz      .loop
%if BPP > 8
        cmp     byte [g_stretch], 0
        jne     .loop
%endif
        call    same_surf
        jne     .loop
        mov     ax, [g_sy]
        cmp     ax, [g_y]
        jge     .loop
        mov     word [g_dir], -1
        mov     ax, [g_h]
        dec     ax
        mov     [g_row], ax
.loop:  mov     cx, [g_h]
.rl:    push    cx
        mov     ax, [g_row]
        ; source
        test    byte [g_ropf], ROPF_S
        jz      .nos
        push    ax
%if BPP > 8
        cmp     byte [g_stretch], 0
        je      .rd
        call    stretch_row
        jmp     .cv
.rd:
%endif
        add     ax, [g_sy]
        mov     bx, src
        mov     cx, [g_sx]
        mov     dx, [g_w]
        mov     di, SBUF
        call    read_row
.cv:    call    convert_sb
%if BPP = 8
        cmp     word [g_sxl], 0
        je      .nx
        push    bx
        push    cx
        push    si
        mov     bx, [g_sxl]
        mov     si, SBUF
        mov     cx, [g_w]
        call    xlat_row
        pop     si
        pop     cx
        pop     bx
.nx:
%endif
        pop     ax
.nos:   add     ax, [g_y]               ; ax = destination y
        mov     bx, dst
        mov     cx, [g_x]
        mov     dx, [g_w]
        cmp     byte [g_rop], 0xCC
        jne     .ncc
        mov     si, SBUF
        call    write_row
        jmp     .next
.ncc:   test    byte [g_ropf], ROPF_P
        jz      .nop
        call    fill_pb
.nop:   cmp     byte [g_rop], 0xF0
        jne     .nf0
        mov     si, PBUF
        call    write_row
        jmp     .next
.nf0:   test    byte [g_ropf], ROPF_D
        jz      .nod
        mov     di, DBUF
        call    read_row
.nod:   push    ax
        push    bx
        push    cx
        mov     si, PBUF
        mov     bx, SBUF
        mov     di, DBUF
        mov     cx, [g_w]
        call    rop_eval
        pop     cx
        pop     bx
        pop     ax
        mov     si, DBUF
        call    write_row
.next:  mov     ax, [g_dir]
        add     [g_row], ax
        pop     cx
        dec     cx
        jnz     .rl
        ret

; ---------------------------------------------------------------------------
; BitBlt(lpDestDev, DestX, DestY, lpSrcDev, SrcX, SrcY, xExt, yExt, Rop3,
;        lpPBrush, lpDrawMode)
; ---------------------------------------------------------------------------
bb_lpDst        equ 34
bb_dx           equ 32
bb_dy           equ 30
bb_lpSrc        equ 26
bb_sx           equ 24
bb_sy           equ 22
bb_w            equ 20
bb_h            equ 18
bb_rop          equ 14
bb_lpBrush      equ 10
bb_lpDM         equ 6

BitBlt:
        PROLOG
        mov     al, [bp+bb_rop+2]
        mov     [g_rop], al
        call    rop_flags
        mov     [g_ropf], ah
        les     si, [bp+bb_lpDst]
        mov     bx, dst
        call    load_surf
        mov     ax, [bp+bb_dx]
        mov     [g_x], ax
        mov     ax, [bp+bb_dy]
        mov     [g_y], ax
        mov     ax, [bp+bb_w]
        mov     [g_w], ax
        mov     ax, [bp+bb_h]
        mov     [g_h], ax
        mov     byte [g_conv], 0
        test    byte [g_ropf], ROPF_S
        jz      .nosrc
        les     si, [bp+bb_lpSrc]
        mov     ax, es
        or      ax, si
        jz      .fail
        mov     bx, src
        call    load_surf
        mov     ax, [bp+bb_sx]
        mov     [g_sx], ax
        mov     ax, [bp+bb_sy]
        mov     [g_sy], ax
        mov     al, [src+SURF.kind]
        mov     ah, [dst+SURF.kind]
        cmp     al, SK_MONO
        jne     .s1
        cmp     ah, SK_MONO
        je      .nosrc
        mov     byte [g_conv], 1
        jmp     .nosrc
.s1:    cmp     ah, SK_MONO
        jne     .nosrc
        mov     byte [g_conv], 2
.nosrc:
%if BPP = 8
        ; colour copies between memory and the screen go through the palette
        ; translation (memory -> screen) or its inverse (screen -> memory)
        mov     word [g_sxl], 0
        test    byte [g_ropf], ROPF_S
        jz      .nsx
        cmp     byte [g_conv], 0
        jne     .nsx
        cmp     byte [pal_mod], 0
        je      .nsx
        mov     al, [src+SURF.kind]
        mov     ah, [dst+SURF.kind]
        cmp     al, ah
        je      .nsx
        mov     word [g_sxl], pal_xlat
        cmp     ah, SK_SCREEN
        je      .nsx
        mov     word [g_sxl], pal_inv
.nsx:
%endif
%if DEBUG > 1
        DBG     'BB '
        DBGX    [bp+bb_rop+2]
        DBGX    [bp+bb_dx]
        DBGX    [bp+bb_dy]
        DBGX    [bp+bb_w]
        DBGX    [bp+bb_h]
        mov     bx, dst
        call    dbg_surf
        test    byte [g_ropf], ROPF_S
        jz      .dd
        DBG     '<- '
        DBGX    [bp+bb_sx]
        DBGX    [bp+bb_sy]
        mov     bx, src
        call    dbg_surf
.dd:    DBG     13,10
%endif
        call    clip_blt
        jc      .ok
        les     si, [bp+bb_lpDM]
        call    get_dm_colors
        test    byte [g_ropf], ROPF_P
        jz      .nopat
        les     si, [bp+bb_lpBrush]
        mov     ax, es
        or      ax, si
        jz      .ok
        call    build_prow
        jc      .ok
.nopat: call    blt_exclude
        call    blt_rows
        call    blt_unexclude
.ok:    mov     ax, 1
        EPILOG  32
.fail:  xor     ax, ax
        EPILOG  32

; ---------------------------------------------------------------------------
; FastBorder(lpRect, BorderWidth, BorderDepth, Rop3, lpDestDev, lpPBrush,
;            lpDrawMode, lpClipRect)
; ---------------------------------------------------------------------------
fb_lpRect       equ 0x1e
fb_bw           equ 0x1c
fb_bh           equ 0x1a
fb_rop          equ 0x16
fb_lpDst        equ 0x12
fb_lpBrush      equ 0x0e
fb_lpDM         equ 0x0a
fb_lpClip       equ 0x06

FastBorder:
        PROLOG
        mov     al, [bp+fb_rop+2]
        mov     [g_rop], al
        call    rop_flags
        and     ah, ~ROPF_S
        mov     [g_ropf], ah
        les     si, [bp+fb_lpDst]
        mov     bx, dst
        call    load_surf
        les     si, [bp+fb_lpDM]
        call    get_dm_colors
        test    byte [g_ropf], ROPF_P
        jz      .nopat
        les     si, [bp+fb_lpBrush]
        mov     ax, es
        or      ax, si
        jz      .done
        call    build_prow
        jc      .done
.nopat: les     si, [bp+fb_lpClip]
        call    set_clip
        les     si, [bp+fb_lpRect]
        mov     ax, [es:si]
        mov     [fb_l], ax
        mov     ax, [es:si+2]
        mov     [fb_t], ax
        mov     ax, [es:si+4]
        mov     [fb_r], ax
        mov     ax, [es:si+6]
        mov     [fb_b], ax
        ; exclusion over the whole frame
        mov     byte [g_excl], 0
        cmp     byte [dst+SURF.kind], SK_SCREEN
        jne     .ne
        mov     ax, [fb_l]
        mov     bx, [fb_t]
        mov     cx, [fb_r]
        mov     dx, [fb_b]
        call    excl_begin
        mov     byte [g_excl], 1
.ne:    ; top: (L, T, R-bw, T+bh)
        mov     ax, [fb_l]
        mov     bx, [fb_t]
        mov     cx, [fb_r]
        sub     cx, [bp+fb_bw]
        mov     dx, bx
        add     dx, [bp+fb_bh]
        call    fb_piece
        ; right: (R-bw, T, R, B-bh)
        mov     ax, [fb_r]
        sub     ax, [bp+fb_bw]
        mov     bx, [fb_t]
        mov     cx, [fb_r]
        mov     dx, [fb_b]
        sub     dx, [bp+fb_bh]
        call    fb_piece
        ; bottom: (L+bw, B-bh, R, B)
        mov     ax, [fb_l]
        add     ax, [bp+fb_bw]
        mov     bx, [fb_b]
        sub     bx, [bp+fb_bh]
        mov     cx, [fb_r]
        mov     dx, [fb_b]
        call    fb_piece
        ; left: (L, T+bh, L+bw, B)
        mov     ax, [fb_l]
        mov     bx, [fb_t]
        add     bx, [bp+fb_bh]
        mov     cx, ax
        add     cx, [bp+fb_bw]
        mov     dx, [fb_b]
        call    fb_piece
        call    blt_unexclude
.done:  mov     ax, 1
        EPILOG  28

; fb_piece: rectangle ax,bx - cx,dx  intersected with the clip rect, then drawn
fb_piece:
        call    clip_rect
        jc      .r
        call    blt_rows
.r:     ret

; set_clip: es:si -> RECT (or NULL).  Sets clip_* = rect intersect destination.
set_clip:
        xor     ax, ax
        mov     [clip_x0], ax
        mov     [clip_y0], ax
        mov     ax, [dst+SURF.width]
        mov     [clip_x1], ax
        mov     ax, [dst+SURF.height]
        mov     [clip_y1], ax
        mov     ax, es
        or      ax, si
        jz      .r
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

; clip_rect: ax,bx - cx,dx  ∩ clip_*  ->  g_x, g_y, g_w, g_h.  CF=1 if empty.
clip_rect:
        cmp     ax, [clip_x0]
        jge     .a
        mov     ax, [clip_x0]
.a:     cmp     bx, [clip_y0]
        jge     .b
        mov     bx, [clip_y0]
.b:     cmp     cx, [clip_x1]
        jle     .c
        mov     cx, [clip_x1]
.c:     cmp     dx, [clip_y1]
        jle     .d
        mov     dx, [clip_y1]
.d:     sub     cx, ax
        jle     .e
        sub     dx, bx
        jle     .e
        mov     [g_x], ax
        mov     [g_y], bx
        mov     [g_w], cx
        mov     [g_h], dx
        clc
        ret
.e:     stc
        ret

dbg_surf:
%if DEBUG
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .m
        DBG     '[scr] '
        ret
.m:     DBG     '[mem '
        DBGX    [bx+SURF.width]
        DBGX    [bx+SURF.height]
        DBGX    [bx+SURF.wbytes]
        push    ax
        movzx   ax, byte [bx+SURF.planes]
        DBGX    ax
        pop     ax
        DBGX    [bx+SURF.bseg]
        DBGX    [bx+SURF.boff]
        DBGX    [bx+SURF.wplanes]
        DBGX    [bx+SURF.segidx]
        DBGX    [bx+SURF.scanseg]
        DBG     '] '
%endif
        ret
