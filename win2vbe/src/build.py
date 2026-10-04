"""Build the VESA/VBE display drivers for Windows 2.x.

usage: python build.py [--nasm PATH] [--template IBMPS250.DRV] [--out DIR]

Needs NASM (https://www.nasm.us) and the stock IBMPS250.DRV from the Windows 2.x
setup files: its cursors, icons, system bitmaps and OEMBIN resources are copied
into the new drivers.  If --template is not given, IBMPS250.DRV is looked for next
to this script, and otherwise extracted from W20\\IBMPS250.DRV on the disk image.
"""
import argparse, os, re, shutil, subprocess, sys

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


README_TXT = r"""VESA/VBE display drivers for Windows 2.x
=======================================
Dmitry Brant, 2026
https://dmitrybrant.com

VBExxxx  = 8 colours  (like the Windows 2.03 VGA driver)
VBExxxxC = 16 colours

Install: run SETUP from the Windows setup files, choose
"Other (requires disk provided by a hardware manufacturer)"
for the display, enter A:\ (or the directory holding these
files) and pick a resolution.  SETUP replaces WIN.INI; to keep
your settings type  COPY /Y WIN.OLD WIN.INI  in C:\WINDOWS
afterwards.

Requirements: a VESA BIOS (VBE 1.2+) that offers a banked
256-colour mode at the chosen resolution, or the Bochs/QEMU
VBE adapter (QEMU -vga std).

VBELIST.COM lists the modes your video BIOS offers.
"""


def find_template(args):
    if args.template:
        return args.template
    local = os.path.join(HERE, 'IBMPS250.DRV')
    if os.path.exists(local):
        return local


def build_one(nasm, template, outdir, x, y, planes, name, grb, lgo, debug=0):
    colors = 8 if planes == 3 else 16
    desc = 'DISPLAY : 100, 96, 96 : VESA/VBE %dx%d (%d colors)' % (x, y, colors)
    tmp = os.path.join(outdir, name + '.bin')
    subprocess.check_call([nasm, '-f', 'bin', '-DXRES=%d' % x, '-DYRES=%d' % y,
                           '-DNPLANES=%d' % planes, '-DDEBUG=%d' % debug, '-DFIXED=0',
                           '-o', tmp, 'vbe.asm'], cwd=HERE)
    mapfile = os.path.join(HERE, 'out', 'vbe.map')
    m = re.search(r'^\s*([0-9A-F]+)\s+[0-9A-F]+\s+code_end\s*$', open(mapfile).read(), re.M)
    code = (int(m.group(1), 16) + 15) & ~15
    total = os.path.getsize(tmp)
    mkne.build(tmp, os.path.join(outdir, name + '.DRV'), code, total - code, desc, template)
    os.remove(tmp)
    shutil.copyfile(grb, os.path.join(outdir, name + '.GRB'))
    shutil.copyfile(lgo, os.path.join(outdir, name + '.LGO'))
    print('%-9s %4dx%-4d %2d colors  code %5d  data %5d' % (name, x, y, colors, code, total - code))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--nasm', default='nasm')
    ap.add_argument('--template')
    ap.add_argument('--image')
    ap.add_argument('--grb', help='screen grabber to pair with the drivers (default: EGAHIRES.GRB)')
    ap.add_argument('--lgo', help='startup logo code (default: CGA.LGO)')
    ap.add_argument('--out', default=os.path.join(HERE, 'drivers'))
    ap.add_argument('--debug', type=int, default=0)
    ap.add_argument('--floppy', help='also write a 1.44 MB floppy image with all drivers')
    args = ap.parse_args()
    template = find_template(args)
    tdir = os.path.dirname(os.path.abspath(template))
    grb = args.grb or os.path.join(tdir, 'EGAHIRES.GRB')
    lgo = args.lgo or os.path.join(tdir, 'CGA.LGO')
    for f in (grb, lgo):
        if not os.path.exists(f):
            sys.exit('%s not found (copy it from the Windows 2 setup files)' % f)
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    for x, y, p, name in VARIANTS:
        build_one(args.nasm, template, args.out, x, y, p, name, grb, lgo, args.debug)
    vbelist = os.path.join(args.out, 'VBELIST.COM')
    subprocess.check_call([args.nasm, '-f', 'bin', '-o', vbelist, 'vbelist.asm'], cwd=HERE)
    readme = os.path.join(args.out, 'README.TXT')
    open(readme, 'wb').write(README_TXT.replace(chr(10), chr(13) + chr(10)).encode('ascii'))
    if args.floppy:
        import mkfloppy
        files = [readme, vbelist] + [os.path.join(args.out, n + ext) for ext in ('.DRV', '.GRB', '.LGO')
                            for _, _, _, n in VARIANTS]
        mkfloppy.build(args.floppy, files)
        print('floppy image:', args.floppy)


if __name__ == '__main__':
    main()
