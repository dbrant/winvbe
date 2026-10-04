; ---------------------------------------------------------------------------
; Enable / Disable, GDIINFO, screen switching (INT 2Fh), repaint requests
; ---------------------------------------------------------------------------
HSIZE   equ (XRES*13+20)/40             ; mm, same pixel pitch as the VGA driver
VSIZE   equ (YRES*13+20)/40

RC_BITBLT       equ 0x0001
RC_BITMAP64     equ 0x0008
RC_GDI20_OUTPUT equ 0x0010
RC_DI_BITMAP    equ 0x0080
RC_DIBTODEV     equ 0x0200
RASTERCAPS      equ RC_BITBLT | RC_BITMAP64 | RC_GDI20_OUTPUT | RC_DI_BITMAP | RC_DIBTODEV

gdiinfo:
        dw      0x0300                  ; dpVersion
        dw      1                       ; dpTechnology = DT_RASDISPLAY
        dw      HSIZE, VSIZE            ; dpHorzSize, dpVertSize (mm)
        dw      XRES, YRES              ; dpHorzRes, dpVertRes
        dw      1                       ; dpBitsPixel
        dw      NPLANES                 ; dpPlanes
        dw      -1                      ; dpNumBrushes
        dw      NCOLORS*5               ; dpNumPens
        dw      0                       ; futureuse
        dw      0                       ; dpNumFonts
        dw      NCOLORS                 ; dpNumColors
        dw      PDEV_SIZE               ; dpDEVICEsize
        dw      0                       ; dpCurves
        dw      0x22                    ; dpLines: polyline, styled
        dw      8                       ; dpPolygonals: scanline
        dw      0x2004                  ; dpText: TC_CP_STROKE | TC_RA_ABLE
        dw      1                       ; dpClip: CP_RECTANGLE
        dw      RASTERCAPS              ; dpRaster
        dw      36, 36, 51              ; dpAspectX, Y, XY
        dw      102                     ; dpStyleLen
        dw      HSIZE*10, VSIZE*10      ; dpMLoWin
        dw      XRES, -YRES             ; dpMLoVpt
%if HSIZE*50 < 32768
        dw      HSIZE*50, VSIZE*50      ; dpMHiWin
        dw      XRES/2, -(YRES/2)       ; dpMHiVpt
%else
        dw      HSIZE*25, VSIZE*25
        dw      XRES/4, -(YRES/4)
%endif
        dw      325, 325                ; dpELoWin
        dw      254, -254               ; dpELoVpt
        dw      1625, 1625              ; dpEHiWin
        dw      127, -127               ; dpEHiVpt
        dw      2340, 2340              ; dpTwpWin
        dw      127, -127               ; dpTwpVpt
        dw      96, 96                  ; dpLogPixelsX, Y
        dw      4                       ; dpDCManage
        dw      0, 0, 0, 0, 0           ; futureuse3..7
        dw      0, 0, 0                 ; dpPalColors, dpPalReserved, dpPalResolution
GDIINFO_SIZE equ $-gdiinfo

PDEV_SIZE equ 0x23
pdevice:
        dw      0x2000                  ; bmType (non-zero: device)
        dw      XRES, YRES
        dw      XRES/8                  ; bmWidthBytes
        db      NPLANES, 1
        dw      0, 0                    ; bmBits
        dd      0                       ; bmWidthPlanes
        dd      0                       ; bmlpPDevice
        dw      0, 0, 0                 ; huge fields
        dd      0
        db      0, 0, 0

; ---------------------------------------------------------------------------
; Enable(lpDevice, Style, lpDestDevType, lpOutputFile, lpData)
; ---------------------------------------------------------------------------
en_lpDevice     equ 20
en_Style        equ 18

Enable:
        PROLOG
        DBG     'Enable '
        DBGX    [bp+en_Style]
        test    word [bp+en_Style], 1
        jz      .init
        ; InquireInfo: copy GDIINFO
        les     di, [bp+en_lpDevice]
        mov     si, gdiinfo
        mov     cx, GDIINFO_SIZE
        push    ds
        push    cs
        pop     ds
        rep     movsb
        pop     ds
        mov     ax, GDIINFO_SIZE
        jmp     .done
.init:
        les     di, [bp+en_lpDevice]
        mov     si, pdevice
        mov     cx, PDEV_SIZE
        push    ds
        push    cs
        pop     ds
        rep     movsb
        pop     ds
        mov     ah, 0x0F                ; remember current video mode
        int     0x10
        and     al, 0x7F
        mov     [saved_mode], al
        call    get_repaint_proc
        call    set_video_mode
        jc      no_mode                 ; no usable 256-colour mode: does not return
        call    hook_2f
        test    word [winflags], WF_PMODE
        jz      .nvdd
        mov     ax, 0x4000              ; tell the display VDD we repaint ourselves
        int     0x2F
.nvdd:  mov     byte [enabled], 1
        mov     ax, 1
.done:
        DBG     13,10
        EPILOG  18

; no_mode: explain on the text screen why Windows cannot start, then wait
; for a reset (GDI would otherwise call Enable forever on a blank screen).
%defstr RES_X XRES
%defstr RES_Y YRES
no_mode:
        mov     ax, 0x0003
        int     0x10
        mov     si, no_mode_msg
.l:     mov     al, [cs:si]
        inc     si
        or      al, al
        jz      .h
        mov     ah, 0x0E
        mov     bx, 7
        int     0x10
        jmp     .l
.h:     sti
        hlt
        jmp     .h
no_mode_msg:
        db      13, 10, 'Windows display driver: the video BIOS offers no ', RES_X, 'x', RES_Y
        db      ' 256-colour', 13, 10
        db      'VESA mode (and no QEMU/Bochs VBE adapter was found).', 13, 10, 13, 10
        db      'Reset the computer and select a lower resolution in SYSTEM.INI,', 13, 10
        db      'or load a VESA BIOS extension such as UNIVBE first.', 13, 10, 0

; ---------------------------------------------------------------------------
; Disable(lpDevice)
; ---------------------------------------------------------------------------
Disable:
        PROLOG
        DBG     'Disable',13,10
        call    cursor_off
        mov     byte [enabled], 0
        test    word [winflags], WF_PMODE
        jz      .nvdd
        mov     ax, 0x4007              ; VDD resumes saving/restoring the screen
        int     0x2F
.nvdd:  call    unhook_2f
        call    leave_video_mode
        xor     ah, ah
        mov     al, [saved_mode]
        int     0x10
        mov     ax, -1
        EPILOG  4

; ---------------------------------------------------------------------------
; INT 2Fh: Windows/386 display notifications
;   4001h  Windows is being switched to the background
;   4002h  Windows is coming back to the foreground: restore mode, repaint
; ---------------------------------------------------------------------------
hook_2f:
        cmp     byte [hooked_2f], 0
        jne     .r
        mov     byte [hooked_2f], 1
        push    es
        mov     ax, 0x352F
        int     0x21
        mov     ax, bx
        mov     bx, old2f
        call    cs_write_word
        mov     ax, es
        mov     bx, old2f+2
        call    cs_write_word
        pop     es
        push    ds
        mov     dx, int2f_handler
        push    cs
        pop     ds
        mov     ax, 0x252F
        int     0x21
        pop     ds
.r:     ret

unhook_2f:
        cmp     byte [hooked_2f], 0
        je      .r
        mov     byte [hooked_2f], 0
        push    ds
        lds     dx, [cs:old2f]
        mov     ax, 0x252F
        int     0x21
        pop     ds
.r:     ret

int2f_handler:
        cmp     ax, 0x4001
        je      .bg
        cmp     ax, 0x4002
        je      .fg
        jmp     far [cs:old2f]
.bg:    push    ds
        mov     ds, [cs:dataseg]
        pushad
        push    es
        DBG     '2F:4001',13,10
        mov     byte [cur_busy], 1
        mov     byte [cur_shown], 0     ; the screen now belongs to someone else
        mov     byte [enabled], 0
        ; Put the adapter back into a standard VGA mode: the VDD restores only
        ; the standard VGA registers of the DOS session, so extended (SVGA or
        ; DISPI) state left behind would garble or blank its screen.
        call    leave_video_mode
        mov     ax, 0x0003
        int     0x10
        mov     ds, [cs:dataseg]
        mov     byte [cur_busy], 0
        jmp     .done
.fg:    push    ds
        mov     ds, [cs:dataseg]
        pushad
        push    es
        DBG     '2F:4002',13,10
        mov     byte [cur_busy], 1
        call    restore_video_mode
        mov     byte [cur_shown], 0
        mov     byte [enabled], 1
        mov     byte [cur_busy], 0
        call    request_repaint
.done:  pop     es
        popad
        pop     ds
        push    bp
        mov     bp, sp
        and     word [bp+6], 0xFFFE     ; clear CF in the caller's flags
        pop     bp
        iret

; ---------------------------------------------------------------------------
; Repainting: USER's RepaintScreen (USER.275), deferred while USER has
; disabled repaints through UserRepaintDisable.
; ---------------------------------------------------------------------------
get_repaint_proc:
        mov     ax, [repaint_proc]
        or      ax, [repaint_proc+2]
        jnz     .r
        push    ds
        mov     ax, user_name
        push    ds
        push    ax
        KCALL   KERNEL, K_GETMODULEHANDLE
        pop     ds
        or      ax, ax
        jz      .r
        push    ax
        xor     ax, ax
        push    ax
        mov     ax, 275
        push    ax
        KCALL   KERNEL, K_GETPROCADDRESS
        mov     [repaint_proc], ax
        mov     [repaint_proc+2], dx
.r:     ret

request_repaint:
        cmp     byte [repaint_off], 0
        je      .now
        mov     byte [repaint_due], 1
        ret
.now:   mov     ax, [repaint_proc]
        or      ax, [repaint_proc+2]
        jz      .r
        call    far [repaint_proc]
        mov     ds, [cs:dataseg]
.r:     ret

; UserRepaintDisable(BOOL fDisable)
UserRepaintDisable:
        PROLOG
        mov     al, [bp+6]
        mov     [repaint_off], al
        or      al, al
        jnz     .r
        cmp     byte [repaint_due], 0
        je      .r
        mov     byte [repaint_due], 0
        call    request_repaint
.r:     EPILOG  2
