; ---------------------------------------------------------------------------
; Enable / Disable, GDIINFO, mode setting, palette
; ---------------------------------------------------------------------------
HSIZE   equ (XRES*13+20)/40             ; mm, same pixel pitch as the VGA driver
VSIZE   equ (YRES*13+20)/40

gdiinfo:
        dw      0x0201                  ; dpVersion
        dw      1                       ; dpTechnology = DT_RASDISPLAY
        dw      HSIZE, VSIZE            ; dpHorzSize, dpVertSize (mm)
        dw      XRES, YRES              ; dpHorzRes, dpVertRes
%if PACKED
        dw      BPP                     ; dpBitsPixel
        dw      1                       ; dpPlanes
%else
        dw      1                       ; dpBitsPixel
        dw      NPLANES                 ; dpPlanes
%endif
        dw      -1                      ; dpNumBrushes
        dw      NCOLORS*5               ; dpNumPens
        dw      0                       ; futureuse
        dw      0                       ; dpNumFonts
%if BPP = 8
        dw      256                     ; dpNumColors
%else
        dw      NCOLORS                 ; dpNumColors
%endif
        dw      PDEV_SIZE               ; dpDEVICEsize
        dw      0                       ; dpCurves
        dw      0x22                    ; dpLines: polyline, styled
        dw      8                       ; dpPolygonals: scanline
        dw      0x2004                  ; dpText
        dw      0                       ; dpClip
        dw      0x19                    ; dpRaster: BITBLT | BITMAP64 | GDI20_OUTPUT
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
        dw      0, 0, 0, 0, 0
GDIINFO_SIZE equ $-gdiinfo

PDEV_SIZE equ 0x23
pdevice:
        dw      0xA000                  ; bmType (non-zero: device)
        dw      XRES, YRES
%if PACKED
        dw      XRES*ELEM               ; bmWidthBytes
        db      1, BPP
%else
        dw      XRES/8                  ; bmWidthBytes
        db      NPLANES, 1
%endif
        dw      0, 0xA000               ; bmBits
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
        call    set_video_mode
        jc      no_mode                 ; no usable 256-color mode: does not return
        mov     byte [enabled], 1
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
        db      ' 256-color', 13, 10
        db      'VESA mode (and no QEMU/Bochs VBE adapter was found).', 13, 10, 13, 10
        db      'Reset the computer, run SETUP from the Windows setup files and pick', 13, 10
        db      'a lower resolution, or load a VESA BIOS extension such as UNIVBE first.', 13, 10, 0

; ---------------------------------------------------------------------------
; Disable(lpDevice)
; ---------------------------------------------------------------------------
Disable:
        PROLOG
        DBG     'Disable',13,10
        call    cursor_off
        mov     byte [enabled], 0
        cmp     byte [vmode_kind], VK_DISPI
        jne     .bios
        mov     dx, VBE_INDEX           ; leave Bochs VBE mode
        mov     ax, VBEI_ENABLE
        out     dx, ax
        inc     dx
        xor     ax, ax
        out     dx, ax
.bios:  xor     ah, ah
        mov     al, [saved_mode]
        int     0x10
        mov     ax, -1
        EPILOG  4

%if BPP = 8
%elif NPLANES = 3
palette6:                               ; 6-bit DAC values (EGA bright colors)
        db       0,  0,  0
        db      63, 21, 21
        db      21, 63, 21
        db      63, 63, 21
        db      21, 21, 63
        db      63, 21, 63
        db      21, 63, 63
        db      63, 63, 63
%else
palette6:                               ; Windows VGA 16-color order (plane 0 = red)
        db       0,  0,  0
        db      32,  0,  0
        db       0, 32,  0
        db      32, 32,  0
        db       0,  0, 32
        db      32,  0, 32
        db       0, 32, 32
        db      48, 48, 48
        db      32, 32, 32
        db      63,  0,  0
        db       0, 63,  0
        db      63, 63,  0
        db       0,  0, 63
        db      63,  0, 63
        db       0, 63, 63
        db      63, 63, 63
%endif
