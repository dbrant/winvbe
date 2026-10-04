; ---------------------------------------------------------------------------
; Device-independent bitmaps: DeviceBitmapBits (SetDIBits / GetDIBits on our
; memory bitmaps), DIBScreenBlt (SetDIBitsToDevice), CreateBitmap stub.
; DIB rows are converted to/from the row engine's one-byte-per-pixel buffers
; (SBUF) in chunks of DIB_CHUNK pixels.  Uncompressed 1, 4, 8 and 24 bpp.
; ---------------------------------------------------------------------------
DIB_CHUNK       equ 512                 ; multiple of 8, <= MAXW

; dib_parse: es:di -> BITMAPINFO.  CF=1 if the format is not supported.
dib_parse:
        push    eax
        push    ecx
        mov     eax, [es:di]            ; header size
        mov     [dib_ctab], di
        add     [dib_ctab], ax
        mov     [dib_ctab+2], es
        cmp     eax, 12
        jne     .info
        mov     byte [dib_csize], 3     ; BITMAPCOREHEADER / RGBTRIPLE
        mov     ax, [es:di+4]
        mov     [dib_w], ax
        mov     ax, [es:di+6]
        mov     [dib_h], ax
        cmp     word [es:di+8], 1
        jne     .bad
        mov     ax, [es:di+10]
        mov     [dib_bpp], ax
        xor     cx, cx
        jmp     .chk
.info:  cmp     eax, 40
        jb      .bad
        mov     byte [dib_csize], 4
        cmp     word [es:di+6], 0       ; width, height < 64K
        jne     .bad
        cmp     word [es:di+10], 0
        jne     .bad
        mov     ax, [es:di+4]
        mov     [dib_w], ax
        mov     ax, [es:di+8]
        mov     [dib_h], ax
        cmp     word [es:di+0x0C], 1
        jne     .bad
        cmp     dword [es:di+0x10], 0   ; BI_RGB only
        jne     .bad
        mov     ax, [es:di+0x0E]
        mov     [dib_bpp], ax
        mov     cx, [es:di+0x20]        ; biClrUsed
.chk:   mov     ax, [dib_bpp]
        cmp     ax, 1
        je      .ok
        cmp     ax, 4
        je      .ok
        cmp     ax, 8
        je      .ok
        cmp     ax, 24
        jne     .bad
.ok:    ; number of colour table entries
        xor     ax, ax
        cmp     word [dib_bpp], 24
        je      .nc
        mov     ax, 1
        push    cx
        mov     cl, [dib_bpp]
        shl     ax, cl
        pop     cx
        jcxz    .nc
        cmp     cx, ax
        ja      .nc
        mov     ax, cx
.nc:    mov     [dib_ncol], ax
        ; bytes per scan, dword aligned
        movzx   eax, word [dib_w]
        or      ax, ax
        jz      .bad
        test    ax, 0x8000
        jnz     .bad
        movzx   ecx, word [dib_bpp]
        imul    eax, ecx
        add     eax, 31
        shr     eax, 5
        shl     eax, 2
        mov     [dib_stride], eax
        clc
        jmp     .r
.bad:   stc
.r:     pop     ecx
        pop     eax
        ret

; dib_build_xlat: DIB colour index -> physical value (colour index or, for
; [dib_mono], the mono value), from the colour table.
dib_build_xlat:
        pushad
        push    es
        les     si, [dib_ctab]
        xor     di, di
.l:     cmp     di, [dib_ncol]
        jae     .r
        mov     dl, [es:si]             ; blue
        mov     ah, [es:si+1]           ; green
        mov     al, [es:si+2]           ; red
        call    rgb_to_phys
        cmp     byte [dib_mono], 0
        je      .c
        mov     bl, bh
.c:     mov     [dib_xlat+di], bl
        movzx   ax, byte [dib_csize]
        add     si, ax
        inc     di
        jmp     .l
.r:     mov     byte [c24_valid], 0
        pop     es
        popad
        ret

; dib_ptr: eax = linear offset into the DIB bits -> es:si, cx = bytes left in
; that segment (0 = 64K).  Preserves the rest.
dib_ptr:
        push    eax
        push    edx
        movzx   edx, word [dib_bits]
        add     eax, edx
        mov     si, ax
        shr     eax, 16
        mul     word [ahincr]
        add     ax, [dib_bits+2]
        mov     es, ax
        mov     cx, si
        neg     cx
        pop     edx
        pop     eax
        ret

; dib_copy_in: eax = linear offset, cx = count, di -> DS buffer
dib_copy_in:
        pushad
        push    es
        mov     bx, cx
.l:     call    dib_ptr
        jcxz    .all
        cmp     cx, bx
        jbe     .m
.all:   mov     cx, bx
.m:     sub     bx, cx
        movzx   edx, cx
        add     eax, edx
        push    ds
        push    es
        push    ds
        pop     es
        pop     ds
        rep     movsb
        pop     ds
        or      bx, bx
        jnz     .l
        pop     es
        popad
        ret

; dib_copy_out: eax = linear offset, cx = count, si -> DS buffer
dib_copy_out:
        pushad
        push    es
        mov     bx, cx
        mov     bp, si
.l:     call    dib_ptr
        mov     di, si
        mov     si, bp
        jcxz    .all
        cmp     cx, bx
        jbe     .m
.all:   mov     cx, bx
.m:     sub     bx, cx
        movzx   edx, cx
        add     eax, edx
        rep     movsb
        mov     bp, si
        or      bx, bx
        jnz     .l
        pop     es
        popad
        ret

; dib_span: cx = first pixel (multiple of 8), dx = pixels -> eax += byte
; offset of that pixel, cx = bytes covering them.
dib_span:
        push    ebx
        push    edx
        movzx   ebx, cx
        movzx   edx, word [dib_bpp]
        imul    ebx, edx
        shr     ebx, 3
        add     eax, ebx
        pop     edx
        push    edx
        movzx   ebx, dx
        movzx   edx, word [dib_bpp]
        imul    ebx, edx
        add     ebx, 7
        shr     ebx, 3
        mov     cx, bx
        pop     edx
        pop     ebx
        ret

; dib_unpack: eax = linear offset of the scan, cx = first pixel (multiple of
; 8), dx = pixels (<= DIB_CHUNK) -> SBUF = physical values.
dib_unpack:
        pushad
        call    dib_span
        mov     di, DIBRAW
        call    dib_copy_in
        mov     cx, dx
        mov     si, DIBRAW
        mov     di, SBUF
        xor     bx, bx
        mov     ax, [dib_bpp]
        cmp     ax, 1
        je      .b1
        cmp     ax, 4
        je      .b4
        cmp     ax, 8
        je      .b8
.b24:   mov     dl, [si]
        mov     ah, [si+1]
        mov     al, [si+2]
        add     si, 3
        cmp     byte [c24_valid], 0
        je      .new
        cmp     ax, [c24_rg]
        jne     .new
        cmp     dl, [c24_b]
        jne     .new
        mov     bl, [c24_val]
        jmp     .st
.new:   call    rgb_to_phys
        cmp     byte [dib_mono], 0
        je      .c
        mov     bl, bh
.c:     mov     [c24_rg], ax
        mov     [c24_b], dl
        mov     [c24_val], bl
        mov     byte [c24_valid], 1
.st:    mov     [di], bl
        inc     di
        loop    .b24
        jmp     .r
.b8:    mov     bl, [si]
        inc     si
        mov     al, [dib_xlat+bx]
        mov     [di], al
        inc     di
        loop    .b8
        jmp     .r
.b4:    mov     bl, [si]
        inc     si
        shr     bl, 4
        mov     al, [dib_xlat+bx]
        mov     [di], al
        mov     bl, [si-1]
        and     bl, 15
        mov     al, [dib_xlat+bx]
        mov     [di+1], al
        add     di, 2
        sub     cx, 2
        jg      .b4
        jmp     .r
.b1:    mov     dl, [si]
        inc     si
        mov     dh, 8
.b1b:   xor     bx, bx
        shl     dl, 1
        adc     bl, 0
        mov     al, [dib_xlat+bx]
        mov     [di], al
        inc     di
        dec     dh
        jnz     .b1b
        sub     cx, 8
        jg      .b1
.r:     popad
        ret

; dib_build_gout: value read from the bitmap -> DIB index (1/4/8 bpp) or
; colour index (24 bpp).  Source mono flag in [dib_mono].
dib_build_gout:
        push    ax
        push    bx
        push    si
        xor     bx, bx
.l:     mov     al, bl
        cmp     byte [dib_mono], 0
        je      .col
        neg     al                      ; mono 0/1 -> black / white
        and     al, CMASK
        cmp     word [dib_bpp], 1
        jne     .st
        mov     al, bl
        jmp     .st
.col:   cmp     word [dib_bpp], 1
        jne     .st
        mov     si, bx                  ; colour -> 0/1 by brightness
        imul    si, si, 3
        movzx   ax, byte [cs:rgbtab+si]
        push    dx
        movzx   dx, byte [cs:rgbtab+si+1]
        add     ax, dx
        movzx   dx, byte [cs:rgbtab+si+2]
        add     ax, dx
        pop     dx
        cmp     ax, 382
        mov     al, 0
        jb      .st
        inc     al
.st:    mov     [gout+bx], al
        inc     bx
        cmp     bx, 16
        jb      .l
        pop     si
        pop     bx
        pop     ax
        ret

; dib_pack: SBUF = values from read_row; eax = linear offset of the scan,
; cx = first pixel (multiple of 8), dx = pixels -> stored into the DIB.
dib_pack:
        pushad
        push    eax
        push    cx
        push    dx
        mov     di, SBUF                ; clear the tail of the last byte
        add     di, dx
        mov     dword [di], 0
        mov     dword [di+4], 0
        mov     cx, dx
        mov     si, SBUF
        mov     di, DIBRAW
        xor     bx, bx
        mov     ax, [dib_bpp]
        cmp     ax, 1
        je      .b1
        cmp     ax, 4
        je      .b4
        cmp     ax, 8
        je      .b8
.b24:   mov     bl, [si]
        inc     si
        and     bl, 15
        mov     bl, [gout+bx]
        push    bx
        imul    bx, bx, 3
        mov     al, [cs:rgbtab+bx+2]
        mov     [di], al                ; blue
        mov     al, [cs:rgbtab+bx+1]
        mov     [di+1], al
        mov     al, [cs:rgbtab+bx]
        mov     [di+2], al
        pop     bx
        xor     bh, bh
        add     di, 3
        loop    .b24
        jmp     .out
.b8:    mov     bl, [si]
        inc     si
        and     bl, 15
        mov     al, [gout+bx]
        mov     [di], al
        inc     di
        loop    .b8
        jmp     .out
.b4:    mov     bl, [si]
        and     bl, 15
        mov     al, [gout+bx]
        shl     al, 4
        mov     bl, [si+1]
        and     bl, 15
        or      al, [gout+bx]
        mov     [di], al
        inc     di
        add     si, 2
        sub     cx, 2
        jg      .b4
        jmp     .out
.b1:    mov     dh, 8
        xor     al, al
.b1b:   mov     bl, [si]
        inc     si
        and     bl, 15
        shl     al, 1
        or      al, [gout+bx]
        dec     dh
        jnz     .b1b
        mov     [di], al
        inc     di
        sub     cx, 8
        jg      .b1
.out:   pop     dx
        pop     cx
        pop     eax
        call    dib_span
        mov     si, DIBRAW
        call    dib_copy_out
        popad
        ret

; dib_put_ctab: write our colour table into the BITMAPINFO
dib_put_ctab:
        pushad
        push    es
        les     di, [dib_ctab]
        mov     cx, 2
        cmp     word [dib_bpp], 1
        je      .go
        mov     cx, 16
        cmp     word [dib_bpp], 4
        je      .go
        mov     cx, 256
        cmp     word [dib_bpp], 8
        je      .go
        xor     cx, cx
.go:    xor     bx, bx
.l:     cmp     bx, cx
        jae     .r
        xor     eax, eax                ; 00RRGGBB
        cmp     word [dib_bpp], 1
        jne     .c
        or      bx, bx
        jz      .st
        mov     eax, 0xFFFFFF
        jmp     .st
.c:     cmp     bx, NCOLORS
        jae     .st
        mov     si, bx
        imul    si, si, 3
        mov     al, [cs:rgbtab+si]
        shl     eax, 8
        mov     al, [cs:rgbtab+si+1]
        shl     eax, 8
        mov     al, [cs:rgbtab+si+2]
.st:    mov     [es:di], ax
        shr     eax, 16
        mov     [es:di+2], al
        cmp     byte [dib_csize], 3
        je      .t
        mov     byte [es:di+3], 0
        inc     di
.t:     add     di, 3
        inc     bx
        jmp     .l
.r:     pop     es
        popad
        ret

; ---------------------------------------------------------------------------
; DeviceBitmapBits(lpBitmap, fGet, iStart, cScans, lpDIBits, lpBitmapInfo,
;                  lpDrawMode, lpTranslate)
; ---------------------------------------------------------------------------
dbb_lpBitmap    equ 28
dbb_fGet        equ 26
dbb_iStart      equ 24
dbb_cScans      equ 22
dbb_lpBits      equ 18
dbb_lpbi        equ 14

DeviceBitmapBits:
        PROLOG
        sub     sp, 8
        les     di, [bp+dbb_lpbi]
        call    dib_parse
        jc      .fail
        les     si, [bp+dbb_lpBitmap]
        mov     bx, dst
        call    load_surf
        cmp     byte [dst+SURF.kind], SK_SCREEN
        je      .fail
        mov     al, 0
        cmp     byte [dst+SURF.kind], SK_MONO
        jne     .nm
        inc     al
.nm:    mov     [dib_mono], al
        mov     eax, [bp+dbb_lpBits]
        mov     [dib_bits], eax
        ; scans: n = min(cScans, height - iStart)
        mov     ax, [dst+SURF.height]
        sub     ax, [bp+dbb_iStart]
        jle     .fail
        cmp     ax, [bp+dbb_cScans]
        jbe     .n
        mov     ax, [bp+dbb_cScans]
.n:     mov     [bp-8], ax              ; scan count
        mov     ax, [dst+SURF.width]    ; w = min(dib width, bitmap width)
        cmp     ax, [dib_w]
        jbe     .w
        mov     ax, [dib_w]
.w:     mov     [bp-10], ax
        cmp     word [bp+dbb_fGet], 0
        jne     .get
        cmp     dword [dib_bits], 0
        je      .fail
        call    dib_build_xlat
        jmp     .go
.get:   call    dib_put_ctab
        call    dib_build_gout
        cmp     dword [dib_bits], 0
        je      .ret
.go:    xor     si, si                  ; j = supplied scan number
.row:   cmp     si, [bp-8]
        jae     .ret
        mov     ax, [dst+SURF.height]   ; y = height - 1 - (iStart + j)
        dec     ax
        sub     ax, [bp+dbb_iStart]
        sub     ax, si
        mov     [bp-12], ax
        movzx   eax, si
        imul    eax, [dib_stride]
        xor     cx, cx                  ; x
.chunk: mov     dx, [bp-10]
        sub     dx, cx
        jle     .nrow
        cmp     dx, DIB_CHUNK
        jbe     .cw
        mov     dx, DIB_CHUNK
.cw:    push    si
        push    eax
        mov     bx, dst
        cmp     word [bp+dbb_fGet], 0
        jne     .g
        call    dib_unpack
        mov     ax, [bp-12]
        mov     si, SBUF
        call    write_row
        jmp     .nc
.g:     push    eax
        mov     ax, [bp-12]
        mov     di, SBUF
        call    read_row
        pop     eax
        call    dib_pack
.nc:    pop     eax
        pop     si
        add     cx, dx
        jmp     .chunk
.nrow:  inc     si
        jmp     .row
.ret:   mov     ax, [bp-8]
        jmp     .done
.fail:  xor     ax, ax
.done:  EPILOG  26

; ---------------------------------------------------------------------------
; DIBScreenBlt(lpPDevice, DestX, DestY, StartScan, NumScans, lpClipRect,
;              lpDrawMode, lpDIBits, lpBitmapInfo, lpTranslate)
; The DIB's top scan (dib_h - 1) is drawn at screen row DestY.
; ---------------------------------------------------------------------------
dsb_lpPDevice   equ 0x22
dsb_DestX       equ 0x20
dsb_DestY       equ 0x1E
dsb_StartScan   equ 0x1C
dsb_NumScans    equ 0x1A
dsb_lpClip      equ 0x16
dsb_lpBits      equ 0x0E
dsb_lpbi        equ 0x0A

; frame: [bp-8] left [bp-10] top [bp-12] right [bp-14] bottom (screen, exclusive)
DIBScreenBlt:
        PROLOG
        sub     sp, 16
        cmp     byte [enabled], 0
        je      .fail
        les     di, [bp+dsb_lpbi]
        call    dib_parse
        jc      .fail
        mov     eax, [bp+dsb_lpBits]
        or      eax, eax
        jz      .fail
        mov     [dib_bits], eax
        mov     byte [dib_mono], 0
        ; destination rectangle of the supplied scans
        mov     ax, [bp+dsb_DestX]
        mov     [bp-8], ax
        add     ax, [dib_w]
        mov     [bp-12], ax
        mov     ax, [bp+dsb_DestY]
        add     ax, [dib_h]
        sub     ax, [bp+dsb_StartScan]
        mov     [bp-14], ax
        mov     [bp-16], ax             ; row of supplied scan 0, exclusive
        sub     ax, [bp+dsb_NumScans]
        mov     [bp-10], ax
        ; clip to the clip rectangle and the screen
        les     si, [bp+dsb_lpClip]
        mov     ax, es
        or      ax, si
        jz      .scr
        mov     ax, [es:si]
        cmp     [bp-8], ax
        jge     .c1
        mov     [bp-8], ax
.c1:    mov     ax, [es:si+2]
        cmp     [bp-10], ax
        jge     .c2
        mov     [bp-10], ax
.c2:    mov     ax, [es:si+4]
        cmp     [bp-12], ax
        jle     .c3
        mov     [bp-12], ax
.c3:    mov     ax, [es:si+6]
        cmp     [bp-14], ax
        jle     .scr
        mov     [bp-14], ax
.scr:   cmp     word [bp-8], 0
        jge     .s1
        mov     word [bp-8], 0
.s1:    cmp     word [bp-10], 0
        jge     .s2
        mov     word [bp-10], 0
.s2:    cmp     word [bp-12], XRES
        jle     .s3
        mov     word [bp-12], XRES
.s3:    cmp     word [bp-14], YRES
        jle     .s4
        mov     word [bp-14], YRES
.s4:    mov     ax, [bp-8]
        cmp     ax, [bp-12]
        jge     .none
        mov     ax, [bp-10]
        cmp     ax, [bp-14]
        jge     .none
        call    dib_build_xlat
        mov     byte [dst+SURF.kind], SK_SCREEN
        mov     ax, [bp-8]
        mov     bx, [bp-10]
        mov     cx, [bp-12]
        mov     dx, [bp-14]
        call    excl_begin
        mov     di, [bp-10]             ; screen y
.row:   mov     ax, [bp-16]             ; j = row0 - 1 - y
        dec     ax
        sub     ax, di
        movzx   eax, ax
        imul    eax, [dib_stride]
        mov     cx, [bp-8]
        sub     cx, [bp+dsb_DestX]      ; DIB x of the first pixel
        mov     si, [bp-12]
        sub     si, [bp-8]              ; pixels left
.chunk: or      si, si
        jz      .nrow
        push    si
        push    cx
        mov     bx, cx
        and     bx, 7                   ; skip to reach a byte boundary
        and     cx, ~7
        mov     dx, DIB_CHUNK
        sub     dx, bx
        cmp     dx, si
        jbe     .cw
        mov     dx, si
.cw:    push    dx
        add     dx, bx
        call    dib_unpack
        pop     dx                      ; pixels drawn
        add     bx, SBUF
        mov     si, bx
        pop     cx
        push    cx
        add     cx, [bp+dsb_DestX]      ; screen x
        mov     ax, di
        push    eax
        mov     bx, dst
        call    write_row
        pop     eax
        pop     cx
        pop     si
        add     cx, dx
        sub     si, dx
        jmp     .chunk
.nrow:  inc     di
        cmp     di, [bp-14]
        jb      .row
        call    excl_end
.none:  mov     ax, [bp+dsb_NumScans]
        jmp     .done
.fail:  xor     ax, ax
.done:  EPILOG  0x20

; CreateBitmap: not supported (GDI keeps device-independent bitmaps itself)
CreateBitmap:
        mov     ax, ds
        nop
        xor     ax, ax
        retf

; SaveScreenBitmap(lpRect, Command): not supported
SaveScreenBitmap:
        xor     ax, ax
        retf    6
