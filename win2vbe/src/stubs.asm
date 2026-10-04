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
        jmp     .done
.gct:   cmp     bx, GETCOLORTABLE
        jne     .done
        les     di, [bp+10]
        mov     bx, [es:di]
        cmp     bx, NCOLORS
        jae     .done
        imul    bx, bx, 3
        les     di, [bp+6]
        mov     ax, [cs:rgbtab+bx]
        mov     [es:di], ax
        mov     al, [cs:rgbtab+bx+2]
        xor     ah, ah
        mov     [es:di+2], ax
.yes:   mov     ax, 1
.done:  EPILOG  14

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
.ps:    xor     di, di                  ; colour index
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

