"""Build the VESA/VBE display drivers for Windows 3.0.

usage: python build.py [--nasm PATH] [--template VGA.DRV] [--out DIR] [--floppy IMG] [--debug 1]

Needs NASM (https://www.nasm.us) and the stock Windows 3.0 VGA.DRV: its cursors,
icons, system bitmaps and OEM resources are copied into the new drivers.
"""
import argparse, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkne

# (xres, yres, planes, name)
VARIANTS = [
    (800, 600, 4, 'VBE800'), (1024, 768, 4, 'VBE1024'), (1152, 864, 4, 'VBE1152'),
    (1280, 1024, 4, 'VBE1280'), (1600, 1200, 4, 'VBE1600'), (1920, 1080, 4, 'VBE1920'),
]

README_TXT = r"""VESA/VBE display drivers for Windows 3.0
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

16-colour drivers for 800x600 up to 1920x1080, for real, standard
and 386 enhanced mode.  A 386 or later CPU is required.

Install:
 1. Copy the VBExxxx.DRV file for the resolution you want into
    C:\WINDOWS\SYSTEM.
 2. In C:\WINDOWS\SYSTEM.INI, section [boot], set
        display.drv=vbe1024.drv
    (keep the VGA grabbers, fonts and display=*vddvga lines).
 3. Start Windows.  If the video BIOS has no 256-colour mode at that
    resolution, a message on the text screen says so; set
    display.drv=vga.drv again from DOS.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked 256-colour
mode at the chosen resolution, or the Bochs/QEMU VBE adapter
(QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
"""


def build_one(nasm, template, outdir, x, y, planes, name, debug=0):
    colors = 8 if planes == 3 else 16
    desc = 'DISPLAY : 100, 96, 96 : VESA/VBE %dx%d (%d colors)' % (x, y, colors)
    tmp = os.path.join(HERE, 'out', name + '.bin')
    subprocess.check_call([nasm, '-f', 'bin', '-DXRES=%d' % x, '-DYRES=%d' % y,
                           '-DNPLANES=%d' % planes, '-DDEBUG=%d' % debug,
                           '-o', tmp, 'vbe.asm'], cwd=HERE)
    mapfile = os.path.join(HERE, 'out', 'vbe.map')
    code, data, nrel = mkne.build(tmp, mapfile, os.path.join(outdir, name + '.DRV'), desc, template)
    os.remove(tmp)
    print('%-8s %4dx%-4d %2d colors  code %5d  data %5d  relocs %d' % (name, x, y, colors, code, data, nrel))


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
    if args.floppy:
        import mkfloppy
        files = [os.path.join(args.out, n) for n in ['README.TXT', 'VBELIST.COM'] +
                 [v[3] + '.DRV' for v in VARIANTS]]
        mkfloppy.build(args.floppy, files)
        print('floppy image:', args.floppy)


if __name__ == '__main__':
    main()
