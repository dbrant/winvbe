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
                align   2
tmp_pat         times 72 db 0

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
g_bk            db      0
g_bkm           db      0
g_fg            db      0
g_fgm           db      0
g_psolid        db      0
g_pval          db      0
g_hatch         db      0
g_transp        db      0
fill_val        db      0
rop_cached      db      0
rop_valid       db      0
                align   2
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
ln_bkval        db      0
ln_rop3         db      0
ln_mask         dd      0
ln_bit          dd      0
sl_target       db      0
tx_brk          db      0
tx_fg           db      0
tx_bk           db      0
tx_count        dw      0
tx_row          dw      0
tx_r            dw      0
tx_cx           dw      0
ft_seg          dw      0
ft_h            dw      0

pentab          times 16 db 0
fgtab           times 16 db 0
bktab           times 16 db 0
prow            times 64 db 0
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
cur_tmp         times 32 db 0
cur_and         times 128 db 0xFF
cur_xor         times 128 db 0
cur_save        times 1024 db 0

                align   4
roptab          times ROPTAB_SIZE db 0

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
c24_val         db      0
c24_valid       db      0
dib_csize       db      0
dib_mono        db      0
gout            times 16 db 0
dib_xlat            times 256 db 0
                align   16
DIBRAW          times DIB_CHUNK*3+16 db 0

                align   16
                times 16 db 0
PBUF              times ROWBUF db 0
                times 16 db 0
SBUF              times ROWBUF db 0
                times 16 db 0
DBUF              times ROWBUF db 0
                times 16 db 0
data_end:
