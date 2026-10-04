"""Build the VESA/VBE display drivers for Windows 1.0x.

usage: python build.py [--nasm PATH] [--template EGAHIRES.DRV] [--out DIR] [--debug 1]

Needs NASM (https://www.nasm.us) and the stock Windows 1.0x EGAHIRES.DRV: its
cursors, icons and system bitmaps are copied into the new drivers.
"""
import argparse, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mkne

# (xres, yres, planes, name)
VARIANTS = [
    (800, 600, 3, 'VBE800'), (800, 600, 4, 'VBE800C'),
    (1024, 768, 3, 'VBE1024'), (1024, 768, 4, 'VBE1024C'),
    (1152, 864, 3, 'VBE1152'), (1152, 864, 4, 'VBE1152C'),
    (1280, 1024, 3, 'VBE1280'), (1280, 1024, 4, 'VBE1280C'),
    (1600, 1200, 3, 'VBE1600'), (1600, 1200, 4, 'VBE1600C'),
    (1920, 1080, 3, 'VBE1920'), (1920, 1080, 4, 'VBE1920C'),
]

# Windows 1 SETUP copies <driver>.GRB and <driver>.LGO with the driver.  Like
# the stock EGA drivers', ours just name the real files: the EGA grabber and
# the CGA logo.
GRB_TEXT = b'egalores.grb\r\n\x1a'
LGO_TEXT = b'cga.lgo\r\n'

README_TXT = r"""VESA/VBE display drivers for Windows 1.0x
=========================================
Dmitry Brant, 2026
https://dmitrybrant.com

VBExxxx  = 8 colours  (like the Windows 1.0x EGA driver)
VBExxxxC = 16 colours
A 386 or later CPU is required.

Windows 1.0x SETUP builds the display driver into WIN100.BIN,
so the driver is installed with SETUP:

 1. Copy all files from the Windows 1.0x setup disks into one
    directory, e.g. C:\WINSETUP, and copy the driver's .DRV,
    .GRB and .LGO files from this disk there as well.
 2. In that directory run MKSETUP with the driver's name:
        MKSETUP VBE1024C
    This writes VBESETUP.EXE, a copy of SETUP.EXE whose
    "EGA (more than 64K)" entry installs the VBE driver.
 3. To update an existing Windows installation run
        VBESETUP /Q C:\WINDOWS USA.DRV MOUSE.DRV VBE1024C.DRV
    (with your keyboard and mouse drivers), or run VBESETUP
    for a new installation and choose "VESA/VBE display driver".

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked
256-colour mode at the chosen resolution, or the Bochs/QEMU
VBE adapter (QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
"""


def build_one(nasm, template, outdir, x, y, planes, name, debug=0):
    colors = 8 if planes == 3 else 16
    desc = 'DISPLAY : VESA/VBE %dx%d (%d colors)' % (x, y, colors)
    tmp = os.path.join(HERE, 'out', name + '.bin')
    subprocess.check_call([nasm, '-f', 'bin', '-DXRES=%d' % x, '-DYRES=%d' % y,
                           '-DNPLANES=%d' % planes, '-DDEBUG=%d' % debug,
                           '-o', tmp, 'vbe.asm'], cwd=HERE)
    mapfile = os.path.join(HERE, 'out', 'vbe.map')
    code, data, _ = mkne.build(tmp, mapfile, os.path.join(outdir, name + '.DRV'), desc, template)
    os.remove(tmp)
    open(os.path.join(outdir, name + '.GRB'), 'wb').write(GRB_TEXT)
    open(os.path.join(outdir, name + '.LGO'), 'wb').write(LGO_TEXT)
    print('%-9s %4dx%-4d %2d colors  code %5d  data %5d' % (name, x, y, colors, code, data))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--nasm', default='nasm')
    ap.add_argument('--template', default=os.path.join(HERE, 'EGAHIRES.DRV'))
    ap.add_argument('--out', default=os.path.join(HERE, '..', 'drivers'))
    ap.add_argument('--debug', type=int, default=0)
    ap.add_argument('--only', help='build just this variant (e.g. VBE1024C)')
    ap.add_argument('--floppy', help='also write a 1.44 MB floppy image with all drivers')
    args = ap.parse_args()
    if not os.path.exists(args.template):
        sys.exit('%s not found (copy EGAHIRES.DRV from the Windows 1.0x setup disk)' % args.template)
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    for x, y, p, name in VARIANTS:
        if args.only and name != args.only.upper():
            continue
        build_one(args.nasm, args.template, args.out, x, y, p, name, args.debug)
    if not args.only:
        for tool in ('VBELIST', 'MKSETUP'):
            subprocess.check_call([args.nasm, '-f', 'bin', '-o', os.path.join(args.out, tool + '.COM'),
                                   tool.lower() + '.asm'], cwd=HERE)
        open(os.path.join(args.out, 'README.TXT'), 'wb').write(
            README_TXT.replace(chr(10), chr(13) + chr(10)).encode('ascii'))
    if args.floppy:
        import mkfloppy
        files = [os.path.join(args.out, n) for n in ('README.TXT', 'MKSETUP.COM', 'VBELIST.COM')]
        files += [os.path.join(args.out, v[3] + ext) for v in VARIANTS for ext in ('.DRV', '.GRB', '.LGO')]
        mkfloppy.build(args.floppy, files)
        print('floppy image:', args.floppy)


if __name__ == '__main__':
    main()
