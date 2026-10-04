; ---------------------------------------------------------------------------
; Video hardware: mode setting (VESA BIOS, or Bochs/QEMU DISPI registers),
; bank switching and split-aware access to spans of the 8bpp frame buffer.
; A span may cross a window boundary when the scanline pitch is not a power
; of two; scr_span hands out the contiguous part.
; ---------------------------------------------------------------------------
%if XRES = 640 && YRES = 480
STDMODE         equ 0x101
%elif XRES = 800 && YRES = 600
STDMODE         equ 0x103
%elif XRES = 1024 && YRES = 768
STDMODE         equ 0x105
%elif XRES = 1280 && YRES = 1024
STDMODE         equ 0x107
%else
STDMODE         equ 0
%endif
MAXMODES        equ (ROWBUF / 2 - 2)

; set_video_mode: CF=1 if no usable 256-colour mode was found
set_video_mode:
        mov     byte [vmode_kind], VK_NONE
        call    try_vbe
        jnc     .ok
        call    try_dispi
        jc      .r
.ok:
%if DEBUG
        DBG     'mode kind='
        movzx   ax, byte [vmode_kind]
        DBGX    ax
        DBG     'vbe='
        DBGX    [vbe_mode]
        DBG     'pitch='
        DBGX    [scr_pitch]
        DBG     'mult='
        DBGX    [bank_mult]
        DBG     'shift='
        movzx   ax, byte [bank_shift]
        DBGX    ax
        DBG     'segs='
        DBGX    [win_rseg]
        DBGX    [win_wseg]
        DBG     'both='
        movzx   ax, byte [win_both]
        DBGX    ax
        DBG     'func='
        DBGX    [win_func+2]
        DBGX    [win_func]
        DBG     13,10
%endif
        mov     word [cur_bank], -1
        call    set_palette
        call    clear_screen
        clc
.r:     ret

; ---------------------------------------------------------------------------
; VESA BIOS extensions
; ---------------------------------------------------------------------------
try_vbe:
        push    ds
        pop     es
        mov     di, DBUF                ; VbeInfoBlock
        mov     cx, 256
        xor     ax, ax
        rep     stosw
        mov     di, DBUF
        mov     ax, 0x4F00
        int     0x10
        mov     ds, [cs:dataseg]
        cmp     ax, 0x004F
        jne     .fail
        cmp     dword [DBUF], 'VESA'
        jne     .fail
        ; copy the mode list (it may live inside the info block)
        push    ds
        pop     es
        mov     di, SBUF
        mov     cx, MAXMODES
        push    ds
        lds     si, [DBUF+0x0E]
.cp:    lodsw
        stosw
        cmp     ax, 0xFFFF
        je      .cpd
        loop    .cp
        mov     word [es:di], 0xFFFF
.cpd:   pop     ds
        mov     si, SBUF
.next:  lodsw
        cmp     ax, 0xFFFF
        je      .std
        mov     [vbe_mode], ax
        call    vbe_check_mode
        jnc     .found
        jmp     .next
.std:
%if STDMODE
        mov     word [vbe_mode], STDMODE
        call    vbe_check_mode
        jnc     .found
%endif
.fail:  stc
        ret
.found: ; choose the window(s): PBUF holds the ModeInfoBlock
        mov     al, [PBUF+2]            ; window A attributes
        mov     ah, [PBUF+3]            ; window B attributes
        mov     bx, [PBUF+8]            ; window A segment
        mov     dx, [PBUF+0x0A]         ; window B segment
        mov     byte [win_first], 0
        mov     byte [win_both], 0
        mov     cl, al
        and     cl, 7
        cmp     cl, 7                   ; A: exists, readable, writeable
        jne     .w2
        mov     [win_rseg], bx
        mov     [win_wseg], bx
        jmp     .wok
.w2:    mov     cl, ah
        and     cl, 7
        cmp     cl, 7                   ; B alone
        jne     .w3
        mov     [win_rseg], dx
        mov     [win_wseg], dx
        mov     byte [win_first], 1
        jmp     .wok
.w3:    mov     byte [win_both], 1      ; separate read and write windows
        mov     cl, al
        and     cl, 5
        cmp     cl, 5
        jne     .w4
        mov     cl, ah
        and     cl, 3
        cmp     cl, 3
        jne     .fail
        mov     [win_wseg], bx
        mov     [win_rseg], dx
        jmp     .wok
.w4:    mov     cl, al
        and     cl, 3
        cmp     cl, 3
        jne     .fail
        mov     cl, ah
        and     cl, 5
        cmp     cl, 5
        jne     .fail
        mov     [win_rseg], bx
        mov     [win_wseg], dx
.wok:   cmp     word [win_rseg], 0
        je      .fail
        cmp     word [win_wseg], 0
        je      .fail
        ; window size (power of two, at most 64K) and granularity
        mov     ax, [PBUF+6]
        cmp     ax, 64
        jbe     .ws
        mov     ax, 64
.ws:    or      ax, ax
        jz      .fail
        bsf     cx, ax
        mov     dx, 1
        shl     dx, cl
        cmp     dx, ax
        jne     .fail
        add     cl, 10
        mov     [bank_shift], cl
        movzx   eax, ax
        shl     eax, 10
        dec     eax
        mov     [win_mask], eax
        mov     ax, [PBUF+6]
        cmp     ax, 64
        jbe     .wg
        mov     ax, 64
.wg:    mov     cx, [PBUF+4]            ; granularity (K)
        or      cx, cx
        jnz     .gd
        mov     cx, ax
.gd:    xor     dx, dx
        div     cx
        or      dx, dx
        jnz     .fail
        or      ax, ax
        jz      .fail
        mov     [bank_mult], ax
        mov     eax, [PBUF+0x0C]
        mov     [win_func], eax
        movzx   eax, word [PBUF+0x10]   ; bytes per scan line
        cmp     ax, XRES
        jb      .fail
        mov     [scr_pitch], eax
        ; set the mode
        mov     ax, 0x4F02
        mov     bx, [vbe_mode]
        int     0x10
        mov     ds, [cs:dataseg]
        cmp     ax, 0x004F
        jne     .fail
        mov     byte [vmode_kind], VK_VBE
        clc
        ret

; vbe_check_mode: [vbe_mode] -> CF=0 if it is XRES x YRES, 8bpp packed.
; Leaves the ModeInfoBlock in PBUF.  Preserves all registers.
vbe_check_mode:
        pusha
        push    es
        push    ds
        pop     es
        mov     di, PBUF
        mov     cx, 128
        xor     ax, ax
        rep     stosw
        mov     di, PBUF
        mov     cx, [vbe_mode]
        mov     ax, 0x4F01
        int     0x10
        mov     ds, [cs:dataseg]
        cmp     ax, 0x004F
        jne     .no
        mov     ax, [PBUF]              ; mode attributes
        test    al, 0x01                ; supported by the hardware
        jz      .no
        test    al, 0x10                ; graphics mode
        jz      .no
        test    al, 0x02                ; resolution information present?
        jz      .noext
        cmp     word [PBUF+0x12], XRES
        jne     .no
        cmp     word [PBUF+0x14], YRES
        jne     .no
        cmp     byte [PBUF+0x19], 8     ; bits per pixel
        jne     .no
        cmp     byte [PBUF+0x18], 1     ; planes
        jne     .no
        cmp     byte [PBUF+0x1B], 4     ; packed pixel
        jne     .no
        jmp     .yes
.noext: cmp     word [vbe_mode], STDMODE
        jne     .no
        cmp     word [vbe_mode], 0
        je      .no
.yes:   pop     es
        popa
        clc
        ret
.no:    pop     es
        popa
        stc
        ret

; vbe_setwin: bx = window (0 = A, 1 = B), position = cur_bank * bank_mult
vbe_setwin:
        mov     ds, [cs:dataseg]
        mov     ax, [cur_bank]
        mul     word [bank_mult]
        mov     dx, ax
        cmp     dword [win_func], 0
        je      .int
        pushf                           ; the window function may leave interrupts
        call    far [win_func]          ; disabled (SeaVGABIOS starts with CLI and
        popf                            ; returns with RETF)
        ret
.int:   mov     ax, 0x4F05
        int     0x10
        ret

; ---------------------------------------------------------------------------
; Bochs / QEMU DISPI registers (used when the BIOS has no matching mode)
; ---------------------------------------------------------------------------
%macro VBEOUT 2
        mov     dx, VBE_INDEX
        mov     ax, %1
        out     dx, ax
        inc     dx
        mov     ax, %2
        out     dx, ax
%endmacro

try_dispi:
        mov     dx, VBE_INDEX
        mov     ax, VBEI_ID
        out     dx, ax
        inc     dx
        in      ax, dx
        cmp     ax, 0xB0C0
        jb      .no
        cmp     ax, 0xB0CF
        ja      .no
        mov     ax, 0x0013
        int     0x10
        mov     ds, [cs:dataseg]
        VBEOUT  VBEI_ENABLE, 0
        VBEOUT  VBEI_XRES, XRES
        VBEOUT  VBEI_YRES, YRES
        VBEOUT  VBEI_BPP, 8
        VBEOUT  VBEI_ENABLE, 1
        VBEOUT  VBEI_VWIDTH, PITCH
        VBEOUT  VBEI_BANK, 0            ; leaves the index register at BANK
        mov     byte [vmode_kind], VK_DISPI
        mov     dword [scr_pitch], PITCH
        mov     word [win_rseg], 0xA000
        mov     word [win_wseg], 0xA000
        mov     byte [bank_shift], 16
        mov     dword [win_mask], 0xFFFF
        clc
        ret
.no:    stc
        ret

; ---------------------------------------------------------------------------
; Bank switching: ax = bank (window-size units).  Preserves all registers.
; ---------------------------------------------------------------------------
set_bank:
        cmp     ax, [cur_bank]
        jne     .sw
        ret
.sw:    mov     [cur_bank], ax
        cmp     byte [vmode_kind], VK_DISPI
        jne     .vbe
        push    dx
        mov     dx, VBE_DATA
        out     dx, ax
        pop     dx
        ret
.vbe:   pushad
        push    es
        push    ds
        movzx   bx, byte [win_first]
        call    vbe_setwin
        mov     ds, [cs:dataseg]
        cmp     byte [win_both], 0
        je      .d
        movzx   bx, byte [win_first]
        xor     bl, 1
        call    vbe_setwin
.d:     pop     ds
        pop     es
        popad
        ret

; scr_span: ax = y, cx = x, dx = w (> 0).  Selects the bank holding (x, y),
; returns di = offset in the window and cx = number of bytes (<= w) that are
; contiguous there.  Preserves ax, bx, dx, si.
scr_span:
        push    eax
        push    ebx
        push    edx
        movzx   ebx, dx
        movzx   eax, ax
        imul    eax, [scr_pitch]
        movzx   ecx, cx
        add     eax, ecx                ; linear offset
        mov     edx, eax
        mov     cl, [bank_shift]
        shr     edx, cl
        push    eax
        mov     ax, dx
        call    set_bank
        pop     eax
        and     eax, [win_mask]
        mov     di, ax
        mov     ecx, [win_mask]
        inc     ecx
        sub     ecx, eax                ; bytes left in the window
        cmp     ecx, ebx
        jbe     .ok
        mov     ecx, ebx
.ok:    pop     edx
        pop     ebx
        pop     eax
        ret

; scr_read: ax = y, cx = x, dx = w, di -> buffer (DS).  Preserves registers.
scr_read:
        pushad
        push    es
        push    ds
        pop     es
        mov     bx, di
.l:     push    cx
        call    scr_span
        mov     bp, cx
        push    ds
        mov     si, di
        mov     di, bx
        mov     ds, [win_rseg]
        push    cx
        shr     cx, 2
        rep     movsd
        pop     cx
        and     cx, 3
        rep     movsb
        pop     ds
        mov     bx, di
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
        ret

; scr_write: ax = y, cx = x, dx = w, si -> buffer (DS).  Preserves registers.
scr_write:
        pushad
        push    es
        mov     bx, si
.l:     push    cx
        call    scr_span
        mov     bp, cx
        mov     es, [win_wseg]
        mov     si, bx
        push    cx
        shr     cx, 2
        rep     movsd
        pop     cx
        and     cx, 3
        rep     movsb
        mov     bx, si
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
        ret

; scr_fill: ax = y, cx = x, dx = w, value in [fill_val].  Preserves registers.
scr_fill:
        pushad
        push    es
.l:     push    cx
        call    scr_span
        mov     bp, cx
        mov     es, [win_wseg]
        push    ax
        mov     al, [fill_val]
        mov     ah, al
        push    ax
        shl     eax, 16
        pop     ax
        push    cx
        shr     cx, 2
        rep     stosd
        pop     cx
        and     cx, 3
        rep     stosb
        pop     ax
        pop     cx
        add     cx, bp
        sub     dx, bp
        jnz     .l
        pop     es
        popad
        ret

; scr_getpix: ax = y, cx = x -> al.  scr_putpix: ax = y, cx = x, dl = value.
scr_getpix:
        push    cx
        push    dx
        push    di
        push    es
        mov     dx, 1
        call    scr_span
        mov     es, [win_rseg]
        mov     al, [es:di]
        pop     es
        pop     di
        pop     dx
        pop     cx
        ret

scr_putpix:
        push    cx
        push    dx
        push    di
        push    es
        push    dx
        mov     dx, 1
        call    scr_span
        pop     dx
        mov     es, [win_wseg]
        mov     [es:di], dl
        pop     es
        pop     di
        pop     dx
        pop     cx
        ret

clear_screen:
        pushad
        push    es
        mov     eax, [scr_pitch]
        imul    eax, eax, YRES
        add     eax, [win_mask]
        mov     cl, [bank_shift]
        shr     eax, cl
        mov     bx, ax                  ; number of banks
        xor     si, si
.b:     mov     ax, si
        call    set_bank
        mov     es, [win_wseg]
        xor     di, di
        mov     ecx, [win_mask]
        inc     ecx
        shr     ecx, 2
        xor     eax, eax
        rep     stosd
        inc     si
        cmp     si, bx
        jb      .b
        pop     es
        popad
        ret

set_palette:
%if BPP = 4
        mov     dx, 0x3C8
        xor     al, al
        out     dx, al
        inc     dx
        mov     si, palette6
        mov     cx, NCOLORS*3
.l:     mov     al, [cs:si]
        out     dx, al
        inc     si
        loop    .l
%else
        mov     dx, 0x3C8               ; the fixed palette (pal_rgb)
        xor     al, al
        out     dx, al
        inc     dx
        mov     si, pal_rgb
        mov     cx, 256
.l:     mov     al, [si]                ; red, green, blue: 8 -> 6 bits
        shr     al, 2
        out     dx, al
        mov     al, [si+1]
        shr     al, 2
        out     dx, al
        mov     al, [si+2]
        shr     al, 2
        out     dx, al
        add     si, 4
        loop    .l
%endif
        ret
