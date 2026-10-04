; MKSETUP.COM - make a Windows 1.0x SETUP that installs a VESA/VBE driver.
; Dmitry Brant, 2026.
;
; usage (in the directory holding the Windows 1.0x setup files):
;       MKSETUP VBE1024C
; reads SETUP.EXE and writes VBESETUP.EXE, in which the "EGA (more than 64K)"
; display entry installs VBE1024C.DRV instead of EGAHIRES.DRV.  The entry keeps
; the EGA font resolution (133,96,72), which suits the VBE drivers.
;
;                                         nasm -f bin -o MKSETUP.COM mksetup.asm
        org     0x100
        cpu     386

        ; ---- driver name from the command line (1..8 characters)
        mov     si, 0x81
.skip:  lodsb
        cmp     al, ' '
        je      .skip
        cmp     al, 9
        je      .skip
        dec     si
        mov     di, drvname
        xor     cx, cx
.name:  lodsb
        cmp     al, ' '
        jbe     .nend
        cmp     al, '.'
        je      .nend
        cmp     al, 'a'
        jb      .up
        cmp     al, 'z'
        ja      .up
        sub     al, 'a' - 'A'
.up:    stosb
        inc     cx
        cmp     cx, 8
        jbe     .name
        jmp     usage
.nend:  or      cx, cx
        jz      usage
        mov     [namelen], cx

        ; ---- read SETUP.EXE
        mov     ax, 0x3D00
        mov     dx, f_setup
        int     0x21
        jc      e_open
        mov     bx, ax
        mov     ah, 0x3F
        mov     cx, BUFMAX
        mov     dx, buf
        int     0x21
        jc      e_read
        mov     [buflen], ax
        mov     ah, 0x3E
        int     0x21

        ; ---- patch the driver file name
        mov     si, s_ega
        mov     cx, S_EGA_LEN
        call    find
        jc      e_notfound
        push    di
        mov     cx, S_EGA_LEN
        xor     al, al
        rep     stosb                   ; clear the old name
        pop     di
        mov     si, drvname
        mov     cx, [namelen]
        rep     movsb
        mov     si, s_drv
        mov     cx, 4
        rep     movsb

        ; ---- patch the description
        mov     si, s_desc
        mov     cx, S_DESC_LEN
        call    find
        jc      e_notfound
        push    di
        mov     cx, S_DESC_LEN
        xor     al, al
        rep     stosb
        pop     di
        mov     si, s_newdesc
        mov     cx, S_NEWDESC_LEN
        rep     movsb
        mov     si, drvname
        mov     cx, [namelen]
        rep     movsb

        ; ---- write VBESETUP.EXE
        mov     ah, 0x3C
        xor     cx, cx
        mov     dx, f_out
        int     0x21
        jc      e_write
        mov     bx, ax
        mov     ah, 0x40
        mov     cx, [buflen]
        mov     dx, buf
        int     0x21
        jc      e_write
        mov     ah, 0x3E
        int     0x21
        mov     dx, m_done
        call    print
        mov     si, drvname
        mov     cx, [namelen]
.pn:    lodsb
        mov     dl, al
        mov     ah, 2
        int     0x21
        loop    .pn
        mov     dx, m_done2
        call    print
        mov     ax, 0x4C00
        int     0x21

; find: si -> pattern, cx = length -> di = position in buf.  CF=1 if absent.
find:
        mov     di, buf
        mov     bx, [buflen]
        sub     bx, cx
        jb      .no
        add     bx, buf                 ; last possible start
.l:     cmp     di, bx
        ja      .no
        push    si
        push    di
        push    cx
        repe    cmpsb
        pop     cx
        pop     di
        pop     si
        je      .yes
        inc     di
        jmp     .l
.yes:   clc
        ret
.no:    stc
        ret

print:  mov     ah, 9
        int     0x21
        ret

usage:  mov     dx, m_usage
        jmp     fail
e_open: mov     dx, m_open
        jmp     fail
e_read: mov     dx, m_read
        jmp     fail
e_write:
        mov     dx, m_write
        jmp     fail
e_notfound:
        mov     dx, m_nf
fail:   call    print
        mov     ax, 0x4C01
        int     0x21

f_setup db      'SETUP.EXE', 0
f_out   db      'VBESETUP.EXE', 0
s_ega   db      'EGAHIRES.DRV'
S_EGA_LEN equ $-s_ega
s_drv   db      '.DRV'
s_desc  db      'EGA (more than 64K) with Enhanced Color Display'
S_DESC_LEN equ $-s_desc
s_newdesc db    'VESA/VBE display driver '
S_NEWDESC_LEN equ $-s_newdesc

m_usage db      'MKSETUP - make a Windows 1.0x SETUP for a VESA/VBE display driver', 13, 10
        db      13, 10
        db      'usage: MKSETUP driver     (e.g. MKSETUP VBE1024C)', 13, 10
        db      13, 10
        db      'Run it in the directory with the Windows 1.0x setup files and the', 13, 10
        db      'driver files (.DRV, .GRB, .LGO).  It writes VBESETUP.EXE, a copy of', 13, 10
        db      'SETUP.EXE whose "EGA (more than 64K)" display entry installs the driver.', 13, 10, '$'
m_open  db      'Cannot open SETUP.EXE (run MKSETUP in the setup files directory).', 13, 10, '$'
m_read  db      'Cannot read SETUP.EXE.', 13, 10, '$'
m_write db      'Cannot write VBESETUP.EXE.', 13, 10, '$'
m_nf    db      'This SETUP.EXE has no EGA (more than 64K) entry; is it from Windows 1.0x?', 13, 10, '$'
m_done  db      'VBESETUP.EXE written.  Install with:', 13, 10
        db      '    VBESETUP              and choose "VESA/VBE display driver", or', 13, 10
        db      '    VBESETUP /Q C:\WINDOWS USA.DRV MOUSE.DRV $'
m_done2 db      '.DRV', 13, 10
        db      '(use your own keyboard and mouse drivers).', 13, 10, '$'

namelen dw      0
buflen  dw      0
drvname times 9 db 0

BUFMAX  equ     0xA000
buf:
