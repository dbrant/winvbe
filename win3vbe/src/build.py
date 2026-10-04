"""Build the VESA/VBE display drivers for Windows 3.0.

usage: python build.py [--nasm PATH] [--template VGA.DRV] [--out DIR] [--floppy IMG] [--debug 1]

Needs NASM (https://www.nasm.us) and, from Windows 3.0: VGA.DRV (its cursors,
icons, system bitmaps and OEM resources are copied into the new drivers), and the
VGA grabbers, logo and fonts (VGACOLOR.GR2, VGA.GR3, VGALOGO.LGO, VGALOGO.RLE,
VGASYS.FON, VGAFIX.FON, VGAOEM.FON), which are copied next to the drivers and
listed in OEMSETUP.INF for Windows Setup.
"""
import argparse, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkne

# colour depths: bits per pixel -> (name suffix, description)
DEPTHS = {4: ('', '16 colors'), 8: ('P', '256 colors'),
          16: ('H', '65536 colors'), 32: ('T', '16M colors')}
RESOLUTIONS = [(800, 600), (1024, 768), (1152, 864), (1280, 1024), (1600, 1200), (1920, 1080)]

# (xres, yres, bpp, name)
VARIANTS = [(x, y, bpp, 'VBE%d%s' % (x, DEPTHS[bpp][0]))
            for bpp in (4, 8, 16, 32) for x, y in RESOLUTIONS]

# Companion files used with the VGA driver (taken from Windows 3.0): the DOS
# screen grabbers for standard and 386 enhanced mode, the startup logo and the
# system, fixed and terminal fonts.  Windows Setup takes all of them from the
# driver disk once it has read its OEMSETUP.INF.
COMPANIONS = ['VGACOLOR.GR2', 'VGA.GR3', 'VGALOGO.LGO', 'VGALOGO.RLE',
              'VGASYS.FON', 'VGAFIX.FON', 'VGAOEM.FON']


def oemsetup_inf():
    lines = ['[disks]',
             '    1 =. ,"VESA/VBE display drivers for Windows 3.0",oemsetup.inf',
             '',
             '[display]']
    for x, y, bpp, name in VARIANTS:
        lines.append('%-8s = 1:%s.drv, "VESA/VBE %dx%d (%s)", "100,96,96", '
                     '1:vgacolor.gr2, 1:vgalogo.lgo, x:*vddvga, 1:vga.gr3,, 1:vgalogo.rle'
                     % (name.lower(), name.lower(), x, y, DEPTHS[bpp][1]))
    lines += ['',
              '[sysfonts]',
              '1:vgasys.fon,"VGA (640x480) resolution System Font", "100,96,96"',
              '',
              '[fixedfonts]',
              '1:vgafix.fon,"VGA (640x480) resolution Fixed System Font", "100,96,96"',
              '',
              '[oemfonts]',
              '1:vgaoem.fon,"VGA (640x480) resolution Terminal Font (USA/Europe)", "100,96,96",1']
    return ''.join(l + chr(13) + chr(10) for l in lines)


README_TXT = r"""VESA/VBE display drivers for Windows 3.0
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

Drivers for 800x600 up to 1920x1080, for real, standard and 386
enhanced mode.  A 386 or later CPU is required.

  VBExxxx   16 colours
  VBExxxxP  256 colours, with palette manager support
  VBExxxxH  HiColor, 32768 or 65536 colours (15/16 bpp mode)
  VBExxxxT  TrueColor, 16.7 million colours (32 bpp mode)

Install with Windows Setup: run SETUP in C:\WINDOWS from DOS,
select "Display", then "Other (requires disk provided by a
hardware manufacturer)", enter the drive or directory holding
these files (e.g. A:\) and pick a resolution and colour depth.

Or by hand:
 1. Copy the driver you want (e.g. VBE1024P.DRV) into
    C:\WINDOWS\SYSTEM.
 2. In C:\WINDOWS\SYSTEM.INI, section [boot], set
        display.drv=vbe1024p.drv
    (keep the VGA grabbers, fonts and display=*vddvga lines).
 3. Start Windows.  If the video BIOS has no suitable mode at that
    resolution, a message on the text screen says so; set
    display.drv=vga.drv again from DOS.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked mode at
the chosen resolution: 8 bpp packed pixel for the 16- and 256-colour
drivers, 15 or 16 bpp for HiColor, 32 bpp for TrueColor (cards with
only 24 bpp modes cannot use TrueColor).  The Bochs/QEMU VBE adapter
(QEMU -vga std) works too.

VBELIST.COM lists the modes your video BIOS offers.
"""


def build_one(nasm, template, outdir, x, y, bpp, name, debug=0):
    colors = DEPTHS[bpp][1]
    desc = 'DISPLAY : 100, 96, 96 : VESA/VBE %dx%d (%s)' % (x, y, colors)
    tmp = os.path.join(HERE, 'out', name + '.bin')
    subprocess.check_call([nasm, '-f', 'bin', '-DXRES=%d' % x, '-DYRES=%d' % y,
                           '-DBPP=%d' % bpp, '-DDEBUG=%d' % debug,
                           '-o', tmp, 'vbe.asm'], cwd=HERE)
    mapfile = os.path.join(HERE, 'out', 'vbe.map')
    code, data, nrel = mkne.build(tmp, mapfile, os.path.join(outdir, name + '.DRV'), desc, template)
    os.remove(tmp)
    print('%-8s %4dx%-4d %-12s  code %5d  data %5d  relocs %d' % (name, x, y, colors, code, data, nrel))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--nasm', default='nasm')
    ap.add_argument('--template', default=os.path.join(HERE, 'VGA.DRV'))
    ap.add_argument('--out', default=os.path.join(HERE, '..', 'drivers'))
    ap.add_argument('--debug', type=int, default=0)
    ap.add_argument('--only', help='build just this variant (e.g. VBE1024)')
    ap.add_argument('--floppy', help='also write a 1.44 MB floppy image with all drivers')
    args = ap.parse_args()
    if not os.path.exists(args.template):
        sys.exit('%s not found (copy VGA.DRV from the Windows 3.0 disks)' % args.template)
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    for x, y, p, name in VARIANTS:
        if args.only and name != args.only.upper():
            continue
        build_one(args.nasm, args.template, args.out, x, y, p, name, args.debug)
    if not args.only:
        subprocess.check_call([args.nasm, '-f', 'bin', '-o', os.path.join(args.out, 'VBELIST.COM'),
                               'vbelist.asm'], cwd=HERE)
        open(os.path.join(args.out, 'README.TXT'), 'wb').write(
            README_TXT.replace(chr(10), chr(13) + chr(10)).encode('ascii'))
        open(os.path.join(args.out, 'OEMSETUP.INF'), 'wb').write(oemsetup_inf().encode('ascii'))
        for f in COMPANIONS:
            src = os.path.join(HERE, f)
            if not os.path.exists(src):
                sys.exit('%s not found (copy it from the Windows 3.0 disks)' % src)
            shutil.copyfile(src, os.path.join(args.out, f))
    if args.floppy:
        import mkfloppy
        files = [os.path.join(args.out, n) for n in ['OEMSETUP.INF', 'README.TXT', 'VBELIST.COM'] +
                 [v[3] + '.DRV' for v in VARIANTS] + COMPANIONS]
        mkfloppy.build(args.floppy, files)
        print('floppy image:', args.floppy)


if __name__ == '__main__':
    main()
