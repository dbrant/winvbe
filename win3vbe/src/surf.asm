; ---------------------------------------------------------------------------
; Surfaces: descriptors, row read/write, single pixels
; All routines expect DS = DGROUP.
; ---------------------------------------------------------------------------

; load_surf: es:si -> GDI BITMAP or our PDEVICE, bx -> SURF (in DS)
load_surf:
        push    ax
        push    dx
        cmp     word [es:si+bmType], 0
        jne     .scr
        mov     ax, [es:si+bmWidth]
        mov     [bx+SURF.width], ax
        mov     ax, [es:si+bmHeight]
        mov     [bx+SURF.height], ax
        mov     ax, [es:si+bmWidthBytes]
        mov     [bx+SURF.wbytes], ax
        mov     al, [es:si+bmPlanes]
        mov     [bx+SURF.planes], al
        mov     byte [bx+SURF.kind], SK_MONO
%if PACKED
        cmp     word [es:si+bmPlanes], 0x0101   ; 1 plane, 1 bit per pixel
%else
        cmp     al, 1
%endif
        je      .m
        mov     byte [bx+SURF.kind], SK_COLOR
.m:     mov     ax, [es:si+bmBits]
        mov     [bx+SURF.boff], ax
        mov     ax, [es:si+bmBits+2]
        mov     [bx+SURF.bseg], ax
        mov     ax, [es:si+bmWidthPlanes]
        mov     [bx+SURF.wplanes], ax
        mov     ax, [es:si+bmSegmentIndex]
        mov     [bx+SURF.segidx], ax
        mov     ax, [es:si+bmScanSegment]
        mov     [bx+SURF.scanseg], ax
        movzx   ax, byte [bx+SURF.planes]
        mul     word [bx+SURF.wbytes]
        mov     [bx+SURF.sstride], ax
        jmp     .r
.scr:   mov     byte [bx+SURF.kind], SK_SCREEN
        mov     byte [bx+SURF.planes], NPLANES
        mov     word [bx+SURF.width], XRES
        mov     word [bx+SURF.height], YRES
.r:     pop     dx
        pop     ax
        ret

; same_surf: CF=0, ZF=1 if dst and src describe the same surface
same_surf:
        mov     al, [dst+SURF.kind]
        cmp     al, [src+SURF.kind]
        jne     .r
        cmp     al, SK_SCREEN
        je      .r
        mov     ax, [dst+SURF.boff]
        cmp     ax, [src+SURF.boff]
        jne     .r
        mov     ax, [dst+SURF.bseg]
        cmp     ax, [src+SURF.bseg]
.r:     ret

; row_addr: bx -> memory SURF, ax = y  ->  es:di = row (plane 0), dx = plane stride
; clobbers ax
; Windows 3.0 stores the planes of a colour bitmap interleaved by scan line.
row_addr:
        cmp     word [bx+SURF.segidx], 0
        jne     .huge
        mul     word [bx+SURF.sstride]
        add     ax, [bx+SURF.boff]
        mov     di, ax
        mov     es, [bx+SURF.bseg]
        mov     dx, [bx+SURF.wbytes]
        ret
.huge:  xor     dx, dx
        div     word [bx+SURF.scanseg]
        push    dx
        mul     word [bx+SURF.segidx]
        add     ax, [bx+SURF.bseg]
        mov     es, ax
        pop     ax
        mul     word [bx+SURF.sstride]
        add     ax, [bx+SURF.boff]
        mov     di, ax
        mov     dx, [bx+SURF.wbytes]
        ret

; ---------------------------------------------------------------------------
; read_row: bx -> SURF, ax = y, cx = x, dx = w, di -> buffer (DS)
; Stores w pixel values (colour indices, or 0/1 for mono).  May scribble up to
; 8 bytes before and after the buffer.  Preserves bx, ds.
; ---------------------------------------------------------------------------
read_row:
        push    ax
        push    cx
        push    dx
        push    si
        push    di
        push    es
        push    bp
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .mem
        call    scr_read
        jmp     .done
.mem:
%if PACKED
        cmp     byte [bx+SURF.kind], SK_COLOR
        jne     .mono
        push    dx                      ; packed colour: copy w pixels
        push    di
        call    row_addr
        mov     si, di
        pop     di
        pop     dx
        shl     cx, ESHIFT
        add     si, cx
        mov     cx, dx
        shl     cx, ESHIFT
        push    ds
        push    es
        push    ds
        pop     es
        pop     ds
        rep     movsb
        pop     ds
        jmp     .done
.mono:
%endif
        push    dx                      ; w
        push    di                      ; buffer
        push    cx                      ; x
        call    row_addr                ; es:di row, dx plane stride
        mov     si, di
        mov     bp, dx                  ; bp = plane stride
        pop     cx
        mov     ax, cx
        shr     ax, 3
        add     si, ax                  ; first byte
        and     cx, 7
        pop     di
        sub     di, cx                  ; buffer pos of first byte's pixel 0
        pop     ax
        add     ax, cx
        add     ax, 7
        shr     ax, 3                   ; number of bytes
        mov     [rr_n], ax
        mov     dx, ax
        ; plane 0: store
        push    si
        push    di
        mov     cx, dx
.p0:    movzx   eax, byte [es:si]
        inc     si
        mov     ecx, [cs:exptab+eax*8]
        mov     [di], ecx
        mov     ecx, [cs:exptab+eax*8+4]
        mov     [di+4], ecx
        add     di, 8
        dec     dx
        jnz     .p0
        pop     di
        pop     si
        cmp     byte [bx+SURF.kind], SK_COLOR
%if PACKED && ELEM > 1
        jne     .widen
%else
        jne     .done
%endif
        ; further planes: OR in shifted bits
        mov     cl, 1
.pl:    add     si, bp
        mov     dx, [rr_n]
        push    si
        push    di
.p1:    movzx   eax, byte [es:si]
        inc     si
        push    dx
        mov     edx, [cs:exptab+eax*8]
        shl     edx, cl
        or      [di], edx
        mov     edx, [cs:exptab+eax*8+4]
        shl     edx, cl
        or      [di+4], edx
        pop     dx
        add     di, 8
        dec     dx
        jnz     .p1
        pop     di
        pop     si
        inc     cl
        cmp     cl, [bx+SURF.planes]
        jb      .pl
%if NPLANES = 4
        cmp     byte [bx+SURF.planes], 3
        jne     .done
        mov     cx, [rr_n]              ; 8-colour bitmap -> full-intensity colours
        shl     cx, 3
        mov     si, di
        push    bx
.t8:    movzx   bx, byte [si]
        mov     al, [cs:c8to16+bx]
        mov     [si], al
        inc     si
        loop    .t8
        pop     bx
%endif
%if PACKED && ELEM > 1
        jmp     .done
.widen: ; mono row: one byte per pixel so far; widen to elements, last first
        mov     si, sp
        mov     di, [ss:si+4]           ; the caller's buffer (pushed di)
        mov     si, [ss:si+8]           ; w (pushed dx)
        dec     si
        push    bx
        mov     bx, di
.wd:    movzx   eax, byte [bx+si]
        push    si
        shl     si, ESHIFT
        mov     [bx+si], EA
        pop     si
        dec     si
        jns     .wd
        pop     bx
%endif
.done:  pop     bp
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; ---------------------------------------------------------------------------
; write_row: bx -> SURF, ax = y, cx = x, dx = w, si -> buffer (DS)
; Preserves bx, ds.
; ---------------------------------------------------------------------------
write_row:
        push    ax
        push    cx
        push    dx
        push    si
        push    di
        push    es
        push    bp
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .mem
        call    scr_write
        jmp     .done
.mem:
%if PACKED
        cmp     byte [bx+SURF.kind], SK_COLOR
        jne     .mono
        push    dx                      ; packed colour: copy w pixels
        push    si
        call    row_addr
        pop     si
        pop     dx
        shl     cx, ESHIFT
        add     di, cx
        mov     cx, dx
        shl     cx, ESHIFT
        rep     movsb
        jmp     .done
.mono:
%if ELEM > 1
        push    ax                      ; mono: narrow the elements to bytes
        push    di                      ; (bit 0) in XBUF, then write those
        push    es
        push    cx
        push    ds
        pop     es
        and     cx, 7
        mov     di, XBUF+8
        sub     si, cx                  ; keep the pixels before x for the
        sub     si, cx                  ; column alignment below
%if ELEM = 4
        sub     si, cx
        sub     si, cx
%endif
        sub     di, cx
        add     cx, dx
.nr:    mov     al, [si]
        and     al, 1
        stosb
        add     si, ELEM
        loop    .nr
        pop     cx
        pop     es
        pop     di
        pop     ax
        mov     si, XBUF+8
%endif
%endif
%if NPLANES = 4
        cmp     byte [bx+SURF.planes], 3
        jne     .w16
        push    ax                      ; 8-colour bitmap: translate the row
        push    bx                      ; (with the bytes around it) into XBUF
        push    cx
        push    di
        mov     cx, dx
        add     cx, 16
        sub     si, 8
        mov     di, XBUF
.t16:   movzx   bx, byte [si]
        and     bl, 15
        mov     al, [cs:c16to8+bx]
        mov     [di], al
        inc     si
        inc     di
        loop    .t16
        pop     di
        pop     cx
        pop     bx
        pop     ax
        mov     si, XBUF+8
.w16:
%endif
        ; compute column range and masks
        mov     [wr_x], cx
        mov     [wr_w], dx
        push    si
        call    row_addr                ; es:di, dx = plane stride
        pop     si
        mov     [wr_pstride], dx
        mov     ax, [wr_x]
        mov     cx, ax
        shr     ax, 3
        add     di, ax                  ; first byte column
        and     cx, 7
        sub     si, cx                  ; buffer pos of the first column's pixel 0
        mov     al, 0xFF
        shr     al, cl
        mov     [wr_lmask], al
        mov     ax, [wr_x]
        add     ax, [wr_w]
        dec     ax                      ; last pixel x
        mov     cx, ax
        and     cl, 7
        mov     al, 0xFF
        shr     al, cl
        not     al                      ; bits 7..(7-cl) set
        mov     ah, 0x80
        sar     ah, cl
        mov     [wr_rmask], ah
        ; number of columns
        mov     ax, [wr_x]
        add     ax, [wr_w]
        dec     ax
        shr     ax, 3
        mov     cx, [wr_x]
        shr     cx, 3
        sub     ax, cx
        inc     ax
        mov     [wr_ncols], ax
        cmp     ax, 1
        jne     .mp
        mov     al, [wr_lmask]
        and     [wr_rmask], al
        mov     byte [wr_lmask], 0xFF   ; single column: use rmask only (applied as last)
.mp:    xor     cl, cl                  ; plane
.plane: push    si
        push    di
        mov     bp, [wr_ncols]
        mov     ch, [wr_lmask]
.col:   cmp     bp, 1
        jne     .nl
        and     ch, [wr_rmask]
.nl:    ; gather plane cl from 8 pixel bytes at ds:si
        mov     eax, [si]
        shr     eax, cl
        and     eax, 0x01010101
        imul    eax, eax, 0x80402010
        shr     eax, 28
        mov     edx, [si+4]
        shr     edx, cl
        and     edx, 0x01010101
        imul    edx, edx, 0x80402010
        shr     edx, 28
        shl     al, 4
        or      al, dl
        cmp     ch, 0xFF
        je      .full
        and     al, ch
        mov     ah, ch
        not     ah
        and     ah, [es:di]
        or      al, ah
.full:  mov     [es:di], al
        inc     di
        add     si, 8
        mov     ch, 0xFF
        dec     bp
        jnz     .col
        pop     di
        pop     si
        add     di, [wr_pstride]
        inc     cl
        cmp     cl, [bx+SURF.planes]
        jb      .plane
.done:  pop     bp
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; ---------------------------------------------------------------------------
; get_pixel: bx -> SURF, cx = x, ax = y  ->  EA = value.  Preserves bx, cx.
; ---------------------------------------------------------------------------
get_pixel:
        push    dx
        push    di
        push    es
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .mem
        call    scr_getpix
        jmp     .r
.mem:
%if PACKED
        cmp     byte [bx+SURF.kind], SK_COLOR
        jne     .mono
        push    cx
        call    row_addr
        shl     cx, ESHIFT
        add     di, cx
        mov     EA, [es:di]
        pop     cx
        jmp     .r
.mono:  xor     eax, eax
%endif
        push    cx
        push    si
        call    row_addr                ; es:di, dx = plane stride
        mov     ax, cx
        shr     ax, 3
        add     di, ax
        and     cl, 7
        xor     cl, 7                   ; shift count
        mov     ch, [bx+SURF.planes]
        xor     ah, ah                  ; result
        xor     si, si                  ; plane index
.l:     mov     al, [es:di]
        shr     al, cl
        and     al, 1
        push    cx
        mov     cx, si
        shl     al, cl
        pop     cx
        or      ah, al
        add     di, dx
        inc     si
        dec     ch
        jnz     .l
        mov     al, ah
%if PACKED
        xor     ah, ah
%endif
%if NPLANES = 4
        cmp     byte [bx+SURF.planes], 3
        jne     .g16
        movzx   si, al
        mov     al, [cs:c8to16+si]
.g16:
%endif
        pop     si
        pop     cx
.r:     pop     es
        pop     di
        pop     dx
        ret

; put_pixel: bx -> SURF, cx = x, ax = y, ED = value.  Preserves bx, cx, edx.
put_pixel:
        push    ax
        push    di
        push    es
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .mem
        call    scr_putpix
        jmp     .r
.mem:
%if PACKED
        cmp     byte [bx+SURF.kind], SK_COLOR
        jne     .mono
        push    cx
        push    edx
        call    row_addr
        pop     edx
        shl     cx, ESHIFT
        add     di, cx
        mov     [es:di], ED
        pop     cx
        jmp     .r
.mono:
%endif
        push    cx
        push    dx
        push    dx
        call    row_addr                ; dx = plane stride
        mov     ax, cx
        shr     ax, 3
        add     di, ax
        and     cl, 7
        mov     ch, 0x80
        shr     ch, cl                  ; bit mask
        pop     ax                      ; al = value
%if NPLANES = 4
        cmp     byte [bx+SURF.planes], 3
        jne     .p16
        push    bx
        movzx   bx, al
        and     bl, 15
        mov     al, [cs:c16to8+bx]
        pop     bx
.p16:
%endif
        mov     cl, [bx+SURF.planes]
.l:     shr     al, 1
        jc      .one
        not     ch
        and     [es:di], ch
        not     ch
        jmp     .n
.one:   or      [es:di], ch
.n:     add     di, dx
        dec     cl
        jnz     .l
        pop     dx
        pop     cx
.r:     pop     es
        pop     di
        pop     ax
        ret

; ---------------------------------------------------------------------------
; fill_row: bx -> SURF, ax = y, cx = x, dx = w, al value -> uses rowbuf DBUF
; ---------------------------------------------------------------------------
fill_row_val:                           ; ah = value, ax high? -> value in [fill_val]
        push    ax
        push    cx
        push    dx
        push    di
        push    es
        cmp     byte [bx+SURF.kind], SK_SCREEN
        jne     .mem
        call    scr_fill
        jmp     .r
.mem:   push    si
        push    ds
        pop     es
.mc:    or      dx, dx
        jz      .md
        push    dx
        cmp     dx, MAXW
        jbe     .mn
        mov     dx, MAXW
.mn:    push    ax
        push    cx
        mov     di, DBUF
        mov     cx, dx
        mov     eax, [fill_val]
        rep     STOSE
        pop     cx
        pop     ax
        mov     si, DBUF
        call    write_row
        add     cx, dx
        mov     si, dx
        pop     dx
        sub     dx, si
        jmp     .mc
.md:    pop     si
.r:     pop     es
        pop     di
        pop     dx
        pop     cx
        pop     ax
        ret

%if NPLANES = 4
; 3-plane (8-colour) bitmaps on the 16-colour device: their colours are the
; full-intensity ones (as with the 8-colour drivers), so 1..6 are the bright
; colours and 7 is white.
c8to16  db      0, 9, 10, 11, 12, 13, 14, 15
c16to8  db      0, 1, 2, 3, 4, 5, 6, 7, 7, 1, 2, 3, 4, 5, 6, 7
%endif

; byte -> 8 pixel bytes (bit 7 first), values 0/1
exptab:
%assign b 0
%rep 256
        db      (b>>7)&1, (b>>6)&1, (b>>5)&1, (b>>4)&1, (b>>3)&1, (b>>2)&1, (b>>1)&1, b&1
%assign b b+1
%endrep
