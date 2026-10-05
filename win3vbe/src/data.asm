; ---------------------------------------------------------------------------
; Data segment
; ---------------------------------------------------------------------------
saved_mode      db      3
enabled         db      0
hooked_2f       db      0
repaint_off     db      0
repaint_due     db      0
dispi_bank      db      0
                align   2
winflags        dw      0
sel_a000        dw      0
sel_b000        dw      0
ahincr          dw      0x1000
dos_psel        dw      0
dos_rseg        dw      0
vbe_di          dw      0
repaint_proc    dd      0
user_name       db      'USER', 0
                align   4
rmregs          times 52 db 0
cur_bank        dw      0
vmode_kind      db      0
win_first       db      0
win_both        db      0
bank_shift      db      16
vbe_mode        dw      0
bank_mult       dw      1
win_rseg        dw      0xA000
win_wseg        dw      0xA000
                align   4
win_mask        dd      0xFFFF
win_func        dd      0
scr_pitch       dd      PITCH
pat_planes      db      0
lvl_r           db      0
lvl_g           db      0
lvl_b           db      0
lvl_l           db      0
near_idx        db      0
                align   4
d16_t           times 3 dd 0
d16_a           times 3 dd 0
d16_dx          times 3 dd 0
d16_e           times 3 dd 0
d16_plan        times 64 db 0
d16_solid       dd      0
db_cref         dd      0
nt_tab          dw      0
nt_n            db      0
dib_trans       dd      0               ; DeviceBitmapBits lpTranslate
pi_last         dd      -1              ; pix_index cache
pi_idx          db      0
                align   2
tmp_pat         times 64*ELEM+8 db 0

dst             times SURF_size db 0
src             times SURF_size db 0

g_x             dw      0
g_y             dw      0
g_w             dw      0
g_h             dw      0
g_sx            dw      0
g_sy            dw      0
g_dir           dw      0
g_row           dw      0
g_bkmode        dw      0
g_rop2          dw      0
g_rop           db      0
g_ropf          db      0
g_conv          db      0
g_excl          db      0
g_bkm           db      0
g_fgm           db      0
g_psolid        db      0
g_hatch         db      0
g_transp        db      0
rop_cached      db      0
rop_valid       db      0
g_xlat          db      0               ; palette translation needed (8bpp)
                align   2
g_sxl           dw      0               ; table for source rows (8bpp), or 0
g_stretch       db      0               ; StretchBlt: source rows from stretch_row
st_mx           db      0               ; mirrored in x / y
st_my           db      0
                align   2
st_dx0          dw      0               ; normalised destination / source rectangles
st_dy0          dw      0
st_dw           dw      0
st_dh           dw      0
st_sx0          dw      0
st_sy0          dw      0
st_sw           dw      0
st_sh           dw      0
st_row          dw      0               ; source row being read
st_wx           dw      0               ; source pixels in XBUF: st_wx .. st_wx+st_wn-1
st_wn           dw      0
                align   4
g_bk            dd      0               ; element values (pixels)
g_fg            dd      0
g_pval          dd      0
fill_val        dd      0
fill_pat        dd      0
%if BPP = 16
pix_g6          db      1               ; 1: 5:6:5, 0: 5:5:5
want565         db      0               ; mode search: accept 5:6:5 only
%endif
rr_n            dw      0
ch_x            dw      0
ch_sx           dw      0
ch_w            dw      0
ch_off          dw      0
wr_x            dw      0
wr_w            dw      0
wr_pstride      dw      0
wr_ncols        dw      0
wr_lmask        db      0
wr_rmask        db      0
clip_x0         dw      0
clip_y0         dw      0
clip_x1         dw      0
clip_y1         dw      0
fb_l            dw      0
fb_t            dw      0
fb_r            dw      0
fb_b            dw      0
sc_ptr          dw      0
sc_cnt          dw      0
pl_ptr          dw      0
pl_cnt          dw      0
ln_x0           dw      0
ln_y0           dw      0
ln_x1           dw      0
ln_y1           dw      0
ln_dx           dw      0
ln_dy           dw      0
ln_sx           dw      0
ln_sy           dw      0
ln_style        dw      0
ln_rop3         db      0
tx_brk          db      0
                align   4
ln_bkval        dd      0
ln_fgval        dd      0
ln_mask         dd      0
ln_bit          dd      0
sl_target       dd      0
tx_fg           dd      0
tx_bk           dd      0
tx_count        dw      0
tx_row          dw      0
tx_r            dw      0
tx_cx           dw      0
ft_seg          dw      0
ft_h            dw      0

pentab          times 16 db 0
fgtab           times 16 db 0
bktab           times 16 db 0
                align   4
prow            times 64*ELEM db 0
pmask           times 64 db 0

; cursor
cur_busy        db      0
cur_shown       db      0
cur_valid       db      0
                align   2
cur_hx          dw      0
cur_hy          dw      0
cur_x           dw      0
cur_y           dw      0
cur_sx          dw      0
cur_sy          dw      0
cur_mx          dw      XRES/2
cur_my          dw      YRES/2
cur_x0          dw      0
cur_c0          dw      0
cur_cw          dw      0
cur_tmp         times 32*ELEM db 0
cur_and         times 128 db 0xFF
cur_xor         times 128 db 0
                align   4
cur_osp         dd      0
cur_oss         dw      0

                align   4
%if BITROP
rop_m           times 8 dd 0            ; bitwise ROP: D-function masks per (P,S)
rop_acc         dd      0
rop_cnt         dw      0
%endif

; DIBs
                align   4
dib_bits        dd      0
dib_ctab        dd      0
dib_stride      dd      0
dib_w           dw      0
dib_h           dw      0
dib_bpp         dw      0
dib_ncol        dw      0
c24_rg          dw      0
c24_b           db      0
c24_valid       db      0
dib_csize       db      0
dib_mono        db      0
                align   4
c24_val         dd      0

%if BPP = 8
; palette: RGB+flags per entry (as SetPalette passes them), translation
; tables set by GDI (SetPaletteTranslate) and their inverse
pal_rgb:                                ; the static colors at 0-9 and 246-255
        db        0,   0,   0, 0
        db      128,   0,   0, 0
        db        0, 128,   0, 0
        db      128, 128,   0, 0
        db        0,   0, 128, 0
        db      128,   0, 128, 0
        db        0, 128, 128, 0
        db      192, 192, 192, 0
        db      192, 220, 192, 0
        db      166, 202, 240, 0
        times (246-10)*4 db 0
        db      255, 251, 240, 0
        db      160, 160, 164, 0
        db      128, 128, 128, 0
        db      255,   0,   0, 0
        db        0, 255,   0, 0
        db      255, 255,   0, 0
        db        0,   0, 255, 0
        db      255,   0, 255, 0
        db        0, 255, 255, 0
        db      255, 255, 255, 0
pal_xlat:
%assign i 0
%rep 256
        db      i
%assign i i+1
%endrep
pal_inv:
%assign i 0
%rep 256
        db      i
%assign i i+1
%endrep
pal_mod         db      0               ; translation is not the identity
%endif

; ---- everything below starts out as zeros and is not stored in the file:
; mkne.py writes the segment up to data_init_end, the loader clears the rest
                align   16
data_init_end:
cur_save        times 1024*ELEM db 0
cur_stack       times 2048 db 0         ; private stack for interrupt-time cursor redraws
cur_stack_top:
%if !BITROP
roptab          times ROPTAB_SIZE db 0
%endif
gout            times 256 db 0          ; GetDIBits: element -> DIB index
dib_xlat        times 256 dd 0          ; SetDIBits: DIB index -> element
%if BPP = 8
upd_tab         times 256 db 0          ; UpdateColors translation
%endif
                align   16
DIBRAW          times DIB_CHUNK*3+16 db 0

BUFPAD          equ 8*ELEM+16
                align   16
                times BUFPAD db 0
PBUF              times ROWBUF db 0
                times BUFPAD db 0
SBUF              times ROWBUF db 0
                times BUFPAD db 0
DBUF              times ROWBUF db 0
                times BUFPAD db 0
XBUF            times ROWBUF+BUFPAD db 0
data_end:
