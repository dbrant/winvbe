; ---------------------------------------------------------------------------
; Software cursor (32x32, AND/XOR masks), screen exclusion
; MoveCursor may be called at interrupt time: a semaphore (cur_busy) protects
; the screen.  Whoever holds it may touch VRAM / the bank register.
; ---------------------------------------------------------------------------
CUR_W           equ 32
CUR_H           equ 32

; cur_clip: horizontal clipping of the cursor at cur_sx.
; -> cur_x0 (first screen x), cur_c0 (first cursor column), cur_cw (width).  CF=1 if nothing visible.
cur_clip:
        mov     ax, [cur_sx]
        xor     bx, bx
        or      ax, ax
        jns     .a
        neg     ax
        mov     bx, ax
        xor     ax, ax
.a:     mov     [cur_x0], ax
        mov     [cur_c0], bx
        cmp     bx, CUR_W
        jae     .none
        mov     cx, CUR_W
        sub     cx, bx
        mov     dx, XRES
        sub     dx, ax
        jle     .none
        cmp     cx, dx
        jbe     .b
        mov     cx, dx
.b:     mov     [cur_cw], cx
        clc
        ret
.none:  stc
        ret

; cur_draw: draw cursor at (cur_x, cur_y), saving the background
cur_draw:
        cmp     byte [cur_valid], 0
        je      .r
        cmp     byte [enabled], 0
        je      .r
        pushad
        push    es
        mov     ax, [cur_x]
        mov     [cur_sx], ax
        mov     ax, [cur_y]
        mov     [cur_sy], ax
        call    cur_clip
        jc      .done
        xor     si, si                  ; row
.row:   mov     ax, [cur_sy]
        add     ax, si
        cmp     ax, YRES
        jae     .nrow                   ; also catches negative rows
        ; save the background
        mov     di, si
        shl     di, 5
        add     di, [cur_c0]
        add     di, cur_save
        mov     cx, [cur_x0]
        mov     dx, [cur_cw]
        call    scr_read
        ; compose the cursor row into cur_tmp
        push    si
        mov     bx, si
        shl     bx, 2
        mov     edx, [cur_and+bx]
        bswap   edx                     ; bit 31 = leftmost pixel
        mov     ebp, [cur_xor+bx]
        bswap   ebp
        mov     cx, [cur_c0]
        shl     edx, cl
        shl     ebp, cl
        mov     cx, [cur_cw]
        mov     bx, di
        xor     di, di
.px:    mov     al, [bx]
        shl     edx, 1
        jc      .keep
        xor     al, al
.keep:  shl     ebp, 1
        jnc     .nx
        xor     al, CMASK
.nx:    mov     [cur_tmp+di], al
        inc     bx
        inc     di
        loop    .px
        pop     si
        mov     ax, [cur_sy]
        add     ax, si
        mov     cx, [cur_x0]
        mov     dx, [cur_cw]
        push    si
        mov     si, cur_tmp
        call    scr_write
        pop     si
.nrow:  inc     si
        cmp     si, CUR_H
        jb      .row
.done:  mov     byte [cur_shown], 1
        pop     es
        popad
.r:     ret

; cur_erase: restore the background under the cursor
cur_erase:
        cmp     byte [cur_shown], 0
        je      .r
        pushad
        push    es
        call    cur_clip
        jc      .done
        xor     si, si
.row:   mov     ax, [cur_sy]
        add     ax, si
        cmp     ax, YRES
        jae     .nrow
        push    si
        shl     si, 5
        add     si, [cur_c0]
        add     si, cur_save
        mov     cx, [cur_x0]
        mov     dx, [cur_cw]
        call    scr_write
        pop     si
.nrow:  inc     si
        cmp     si, CUR_H
        jb      .row
.done:  mov     byte [cur_shown], 0
        pop     es
        popad
.r:     ret

; cur_update: bring the cursor on screen up to date (caller holds cur_busy)
cur_update:
        cmp     byte [cur_shown], 0
        je      .notshown
        mov     ax, [cur_x]
        cmp     ax, [cur_sx]
        jne     .redraw
        mov     ax, [cur_y]
        cmp     ax, [cur_sy]
        jne     .redraw
        ret
.redraw:
        call    cur_erase
.notshown:
        call    cur_draw
        ret

; ---------------------------------------------------------------------------
; Exclusion.  excl_begin: ax=x0, bx=y0, cx=x1, dx=y1 (exclusive), screen coords.
; Acquires the semaphore and hides the cursor if it intersects.
; excl_end releases and redraws.
; ---------------------------------------------------------------------------
excl_begin:
        push    di
        mov     byte [cur_busy], 1
        cmp     byte [cur_shown], 0
        je      .r
        mov     di, [cur_sx]
        cmp     cx, di                  ; x1 <= cursor left: no overlap
        jle     .r
        add     di, CUR_W
        cmp     ax, di                  ; x0 >= cursor right
        jge     .r
        mov     di, [cur_sy]
        cmp     dx, di
        jle     .r
        add     di, CUR_H
        cmp     bx, di
        jge     .r
        call    cur_erase
.r:     pop     di
        ret

excl_all:                               ; exclude the whole screen
        push    ax
        push    bx
        push    cx
        push    dx
        xor     ax, ax
        xor     bx, bx
        mov     cx, XRES
        mov     dx, YRES
        call    excl_begin
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

excl_end:
        pusha
        call    cur_update
        popa
        mov     byte [cur_busy], 0
        ret

; ---------------------------------------------------------------------------
; SetCursor(lpCursorShape)
; ---------------------------------------------------------------------------
SetCursor:
        PROLOG
        mov     byte [cur_busy], 1
        call    cur_erase
        les     si, [bp+6]
        mov     ax, es
        or      ax, si
        jnz     .set
        mov     byte [cur_valid], 0
        jmp     .done
.set:   mov     ax, [es:si]             ; csHotX
        mov     [cur_hx], ax
        mov     ax, [es:si+2]           ; csHotY
        mov     [cur_hy], ax
        mov     cx, [es:si+8]           ; csWidthBytes
        mov     dx, [es:si+6]           ; csHeight
        add     si, 12
        ; AND mask then XOR mask, csWidthBytes*csHeight bytes each
        mov     di, cur_and
        call    .copy
        mov     di, cur_xor
        call    .copy
        mov     byte [cur_valid], 1
        mov     ax, [cur_mx]
        sub     ax, [cur_hx]
        mov     [cur_x], ax
        mov     ax, [cur_my]
        sub     ax, [cur_hy]
        mov     [cur_y], ax
        call    cur_draw
.done:  mov     byte [cur_busy], 0
        EPILOG  4
; copy a mask: es:si source (advanced), di dest (128 bytes, 4 per row)
.copy:  push    dx
        push    di
        ; preset to "transparent": AND = FF, XOR = 00
        push    es
        push    ds
        pop     es
        push    cx
        mov     cx, 128
        mov     al, 0xFF
        cmp     di, cur_and
        je      .pre
        xor     al, al
.pre:   rep     stosb
        pop     cx
        pop     es
        pop     di
        xor     bx, bx                  ; row
.cr:    cmp     bx, dx
        jae     .cd
        push    si
        push    di
        push    cx
        cmp     cx, 4
        jbe     .cw
        mov     cx, 4
.cw:    jcxz    .cx
.cb:    mov     al, [es:si]
        cmp     bx, CUR_H
        jae     .cs
        mov     [di], al
.cs:    inc     si
        inc     di
        loop    .cb
.cx:    pop     cx
        pop     di
        pop     si
        add     si, cx
        add     di, 4
        inc     bx
        jmp     .cr
.cd:    pop     dx
        ret

; ---------------------------------------------------------------------------
; MoveCursor(absX, absY)  -- may be called at interrupt time
; ---------------------------------------------------------------------------
MoveCursor:
        PROLOG
        mov     ax, [bp+8]
        mov     [cur_mx], ax
        sub     ax, [cur_hx]
        mov     [cur_x], ax
        mov     ax, [bp+6]
        mov     [cur_my], ax
        sub     ax, [cur_hy]
        mov     [cur_y], ax
        mov     al, 1
        xchg    al, [cur_busy]
        or      al, al
        jnz     .done                   ; screen busy: CheckCursor will catch up
        mov     byte [cur_force], 0     ; redraw only if due (cur_due)
        call    cur_update_ps
        mov     byte [cur_busy], 0
.done:  EPILOG  4

; cur_due: CF=1 if the cursor was drawn less than about 8 ms ago.  Mouse
; events can arrive much faster than a person can see (QEMU's serial mouse
; delivers its queued packets back to back); redrawing for each of them makes
; the mouse interrupt path slow enough for packets to pile up and nest in
; USER, whose mouse stack is small.  Time: the BIOS tick count and the count
; of timer channel 0 (mode 3: decrements by 2 at 1.19 MHz).
cur_due:
        push    ax
        push    bx
        push    es
        xor     ax, ax
        mov     es, ax
        pushf
        cli
        mov     al, 0                   ; latch channel 0
        out     0x43, al
        in      al, 0x40
        mov     ah, al
        in      al, 0x40
        xchg    al, ah                  ; ax = count
        mov     bx, [es:0x46C]          ; BIOS ticks (low word)
        popf
        cmp     bx, [cur_tick]          ; another tick since the last draw
        jne     .yes
        mov     bx, [cur_cnt]
        sub     bx, ax                  ; counts since the last draw
        cmp     bx, 19000               ; ~8 ms
        jb      .no
.yes:   mov     [cur_cnt], ax
        mov     bx, [es:0x46C]
        mov     [cur_tick], bx
        clc
        jmp     .r
.no:    stc
.r:     pop     es
        pop     bx
        pop     ax
        ret

; CheckCursor()
CheckCursor:
        PROLOG
        mov     al, 1
        xchg    al, [cur_busy]
        or      al, al
        jnz     .done
        mov     byte [cur_force], 1
        call    cur_update_ps
        mov     byte [cur_busy], 0
.done:  EPILOG  0

; cur_update_ps: cur_update for MoveCursor / CheckCursor, which run at
; interrupt time:
; * on the driver's own stack: SYSTEM's timer handler calls CheckCursor on a
;   private stack of under 200 bytes, far too little for redrawing the cursor
;   and calling the video BIOS to switch banks;
; * drawing with interrupts disabled: the mouse interrupt handler re-enables
;   interrupts before calling USER, so mouse packets arriving during a redraw
;   would nest into it;
; * MoveCursor redraws only if the last redraw was more than about 8 ms ago
;   (cur_due), CheckCursor always ([cur_force]);
; * then, still on the driver's stack, briefly with the caller's interrupt
;   flag: mouse packets that are waiting are handled here.  USER handles mouse
;   events on a small private stack and nests further events on it; QEMU's
;   serial mouse delivers queued packets back to back, so a backlog nests
;   deeply and overflows that stack.  Taken here, the nested events run on
;   this stack, find cur_busy set and only record the new position, which is
;   drawn next.
; The caller holds cur_busy, so nobody else is using cur_stack.
cur_update_ps:
        pushf
        pop     word [cur_ofl]          ; the caller's flags
        cli
        mov     [cur_oss], ss
        mov     [cur_osp], sp
        mov     ax, ds
        mov     ss, ax
        mov     sp, cur_stack_top
        mov     byte [cur_loops], 4     ; at most 4 rounds per call
.l:     cmp     byte [cur_force], 0
        jne     .draw
        call    cur_due
        jc      .drain
.draw:  mov     byte [cur_force], 0
        call    cur_update
.drain: test    byte [cur_ofl+1], 0x02  ; IF: let pending interrupts in
        jz      .x
        sti
        nop
        cli
        cmp     byte [cur_shown], 0     ; moved meanwhile: another round
        je      .x
        mov     ax, [cur_x]
        cmp     ax, [cur_sx]
        jne     .again
        mov     ax, [cur_y]
        cmp     ax, [cur_sy]
        je      .x
.again: dec     byte [cur_loops]
        jnz     .l
.x:     mov     ss, [cur_oss]
        mov     sp, [cur_osp]
        push    word [cur_ofl]
        popf
        ret

; cursor_off: forget the on-screen cursor (screen is being abandoned)
cursor_off:
        mov     byte [cur_shown], 0
        ret
