; ---------------------------------------------------------------------------
; Raster operations: a cached lookup table result = T[P,S,D] over colour indices
; ---------------------------------------------------------------------------
%if NPLANES = 3
NB              equ 3
%else
NB              equ 4
%endif
ROPTAB_SIZE     equ (1 << (3*NB))

ROPF_P          equ 1
ROPF_S          equ 2
ROPF_D          equ 4

; rop_flags: al = rop3 -> ah = ROPF_* usage flags
rop_flags:
        push    cx
        xor     ah, ah
        mov     cl, al
        shr     cl, 4
        xor     cl, al
        test    cl, 0x0F
        jz      .s
        or      ah, ROPF_P
.s:     mov     cl, al
        shr     cl, 2
        xor     cl, al
        test    cl, 0x33
        jz      .d
        or      ah, ROPF_S
.d:     mov     cl, al
        shr     cl, 1
        xor     cl, al
        test    cl, 0x55
        jz      .r
        or      ah, ROPF_D
.r:     pop     cx
        ret

; build_rop_table: al = rop3.  Rebuilds roptab unless already cached.
build_rop_table:
        cmp     byte [rop_valid], 0
        je      .build
        cmp     al, [rop_cached]
        jne     .build
        ret
.build: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     [rop_cached], al
        mov     byte [rop_valid], 1
        xor     di, di
.l:     xor     dl, dl                  ; result
        xor     cl, cl                  ; bit number
.b:     mov     si, di
        shr     si, cl
        xor     ch, ch                  ; k
        test    si, 1
        jz      .k1
        or      ch, 1
.k1:    test    si, 1 << NB
        jz      .k2
        or      ch, 2
.k2:    test    si, 1 << (2*NB)
        jz      .k3
        or      ch, 4
.k3:    push    cx
        mov     cl, ch
        mov     ah, [rop_cached]
        shr     ah, cl
        pop     cx
        and     ah, 1
        shl     ah, cl
        or      dl, ah
        inc     cl
        cmp     cl, NB
        jb      .b
        mov     [roptab+di], dl
        inc     di
        cmp     di, ROPTAB_SIZE
        jb      .l
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; rop_eval: si -> P, bx -> S, di -> D (in/out), cx = count.  Uses roptab.
rop_eval:
        push    eax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        jcxz    .r
.l:     movzx   ax, byte [si]
        and     al, CMASK
        shl     ax, NB
        mov     dl, [bx]
        and     dl, CMASK
        or      al, dl
        shl     ax, NB
        mov     dl, [di]
        and     dl, CMASK
        or      al, dl
        movzx   eax, ax
        mov     al, [roptab+eax]
        mov     [di], al
        inc     si
        inc     bx
        inc     di
        dec     cx
        jnz     .l
.r:     pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     eax
        ret

; rop2_to_rop3: al = R2_* (1..16) -> al = equivalent rop3 index
rop2_to_rop3:
        push    bx
        dec     al
        and     ax, 15
        mov     bx, ax
        mov     al, [cs:rop2tab+bx]
        pop     bx
        ret

rop2tab:
%assign t 0
%rep 16
 %assign r 0
 %assign k 0
 %rep 8
  %assign r r | (((t >> (((k >> 1) & 2) | (k & 1))) & 1) << k)
  %assign k k+1
 %endrep
        db      r
 %assign t t+1
%endrep

; make_pen_table: al = rop3, dl = pen value -> pentab[d] = result for all d
make_pen_table:
        push    ax
        push    bx
        push    cx
        call    build_rop_table
        movzx   bx, dl
        and     bl, CMASK
        shl     bx, 2*NB
        xor     cx, cx
.l:     mov     al, [roptab+bx]
        push    bx
        mov     bx, cx
        mov     [pentab+bx], al
        pop     bx
        inc     bx
        inc     cx
        cmp     cx, NCOLORS
        jb      .l
        pop     cx
        pop     bx
        pop     ax
        ret
