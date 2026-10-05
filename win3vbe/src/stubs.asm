; ---------------------------------------------------------------------------
; Small DDI entry points
; ---------------------------------------------------------------------------

; EnumDFonts(lpDestDev, lpFaceName, lpCallbackFunc, lpClientData)
EnumDFonts:
        mov     ax, 1
        retf    16

; DeviceBitmap(lpDestDev, Command, lpBitmap, lpBits)
DeviceBitmap:
        xor     ax, ax
        retf    14

; SetAttribute(lpDestDev, StateNum, Index, Attribute)
SetAttribute:
        xor     ax, ax
        retf    12

; DeviceMode(hWnd, hInst, lpDeviceType, lpOutputFile)
DeviceMode:
        mov     ax, -1
        retf    12

; Inquire(lpCursorInfo)
Inquire:
        PROLOG
        les     di, [bp+6]
        mov     word [es:di], 1         ; dpXRate
        mov     word [es:di+2], 2       ; dpYRate
        mov     ax, 4
        EPILOG  4

; Control(lpDestDev, wFunction, lpInData, lpOutData)
QUERYESCSUPPORT equ 8
GETCOLORTABLE   equ 5
SETCOLORTABLE   equ 4
Control:
        PROLOG
        xor     ax, ax
        mov     bx, [bp+14]
        cmp     bx, QUERYESCSUPPORT
        jne     .gct
        les     di, [bp+10]
        mov     bx, [es:di]
        cmp     bx, QUERYESCSUPPORT
        je      .yes
        cmp     bx, GETCOLORTABLE
        je      .yes
%if FIXPAL
        cmp     bx, SETCOLORTABLE
        je      .yes
%endif
        jmp     .done
.gct:
%if FIXPAL
        cmp     bx, SETCOLORTABLE
        je      .sct
%endif
        cmp     bx, GETCOLORTABLE
        jne     .done
        les     di, [bp+10]
        mov     bx, [es:di]
%if FIXPAL
        cmp     bx, 256                 ; the fixed palette: index = pixel value
        jae     .done
        shl     bx, 2
        les     di, [bp+6]
        mov     ax, [pal_rgb+bx]
        mov     [es:di], ax
        mov     al, [pal_rgb+bx+2]
%else
        cmp     bx, NCOLORS
        jae     .done
        imul    bx, bx, 3
        les     di, [bp+6]
        mov     ax, [cs:rgbtab+bx]
        mov     [es:di], ax
        mov     al, [cs:rgbtab+bx+2]
%endif
        xor     ah, ah
        mov     [es:di+2], ax
.yes:   mov     ax, 1
.done:  EPILOG  14
%if FIXPAL
; SETCOLORTABLE: lpInData -> {WORD index; COLORREF color}, lpOutData -> the
; color set.  Applications (PC Paintbrush) load image palettes this way.
.sct:   les     di, [bp+10]
        mov     bx, [es:di]
        cmp     bx, 256
        jae     .done
        mov     eax, [es:di+2]
        and     eax, 0x00FFFFFF
        shl     bx, 2
        mov     [pal_rgb+bx], eax       ; R, G, B, 0
        mov     byte [pal_dirty], 1
        cmp     byte [enabled], 0
        je      .so
        mov     dx, 0x3C8               ; the DAC entry
        shr     bx, 2
        mov     al, bl
        out     dx, al
        inc     dx
        mov     al, [es:di+2]
        shr     al, 2
        out     dx, al
        mov     al, [es:di+3]
        shr     al, 2
        out     dx, al
        mov     al, [es:di+4]
        shr     al, 2
        out     dx, al
.so:    les     di, [bp+6]
        mov     ax, es
        or      ax, di
        jz      .yes
        les     si, [bp+10]
        mov     eax, [es:si+2]
        les     di, [bp+6]
        and     eax, 0x00FFFFFF
        mov     [es:di], eax
        jmp     .yes
%endif

; EnumObj(lpDestDev, wStyle, lpCallbackFunc, lpClientData)
eo_style        equ 14
eo_callback     equ 10
eo_data         equ 6
EnumObj:
        PROLOG
        sub     sp, 16                  ; [bp-22] logical object buffer
        mov     ax, 1
        cmp     word [bp+eo_style], 1
        je      .pens
        cmp     word [bp+eo_style], 2
        je      .brushes
        jmp     .done
.pens:  xor     si, si                  ; style 0..4
.ps:    xor     di, di                  ; color index
.pc:    mov     [bp-22], si             ; lopnStyle
        mov     word [bp-20], 1         ; lopnWidth.x
        mov     word [bp-18], 0
        call    .rgb
        mov     [bp-16], ax
        mov     [bp-14], dx
        call    .call
        jz      .done
        inc     di
        cmp     di, NCOLORS
        jb      .pc
        inc     si
        cmp     si, 5
        jb      .ps
        jmp     .done
.brushes:
        xor     di, di
.bs:    mov     word [bp-22], 0         ; BS_SOLID
        call    .rgb
        mov     [bp-20], ax
        mov     [bp-18], dx
        mov     word [bp-16], 0
        call    .call
        jz      .done
        inc     di
        cmp     di, NCOLORS
        jb      .bs
        xor     si, si                  ; hatched, black
.bh:    mov     word [bp-22], 2
        mov     word [bp-20], 0
        mov     word [bp-18], 0
        mov     [bp-16], si
        call    .call
        jz      .done
        inc     si
        cmp     si, 6
        jb      .bh
        jmp     .done
.rgb:   mov     bx, di
        imul    bx, bx, 3
        mov     ax, [cs:rgbtab+bx]
        movzx   dx, byte [cs:rgbtab+bx+2]
        ret
.call:  push    si
        push    di
        lea     ax, [bp-22]
        push    ss
        push    ax
        push    word [bp+eo_data+2]
        push    word [bp+eo_data]
        call    far [bp+eo_callback]
        mov     ds, [cs:dataseg]
        pop     di
        pop     si
        or      ax, ax
        ret
.done:  EPILOG  14

