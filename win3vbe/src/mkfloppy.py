"""Create a 1.44 MB FAT12 floppy image holding the driver files (for SETUP's "Other" option).

usage: python mkfloppy.py OUT.IMG FILE...
"""
import os, struct, sys

SECT = 512
TOTAL = 2880
RSVD, NFATS, SPF, ROOTENT, SPT, HEADS = 1, 2, 9, 224, 18, 2
ROOTSECT = ROOTENT * 32 // SECT
DATA0 = RSVD + NFATS * SPF + ROOTSECT


def short_name(path):
    base = os.path.basename(path).upper()
    name, _, ext = base.partition('.')
    assert len(name) <= 8 and len(ext) <= 3, base
    return name.ljust(8).encode('ascii') + ext.ljust(3).encode('ascii')


def build(out, files):
    img = bytearray(TOTAL * SECT)
    bs = bytearray(SECT)
    bs[0:3] = b'\xEB\x3C\x90'
    bs[3:11] = b'VBEDRV  '
    struct.pack_into('<HBHBHHBHHHII', bs, 11, SECT, 1, RSVD, NFATS, ROOTENT, TOTAL, 0xF0,
                     SPF, SPT, HEADS, 0, 0)
    bs[36] = 0
    bs[38] = 0x29
    struct.pack_into('<I', bs, 39, 0x1994D0C0)
    bs[43:54] = b'VBE DRIVERS'
    bs[54:62] = b'FAT12   '
    # tiny boot code: print a message and wait
    msg = b'Not a system disk: remove it and press a key.\r\n\0'
    code = bytes([0xFA, 0x31, 0xC0, 0x8E, 0xD8, 0x8E, 0xD0, 0xBC, 0x00, 0x7C, 0xFB,
                  0xBE]) + struct.pack('<H', 0x7C00 + 62 + 32) + bytes([
                  0xAC, 0x08, 0xC0, 0x74, 0x06, 0xB4, 0x0E, 0xCD, 0x10, 0xEB, 0xF5,
                  0x32, 0xE4, 0xCD, 0x16, 0xCD, 0x19])      # wait for a key, retry boot
    bs[62:62 + len(code)] = code
    bs[62 + 32:62 + 32 + len(msg)] = msg
    bs[510:512] = b'\x55\xAA'
    img[0:SECT] = bs

    fat = [0xFF0, 0xFFF] + [0] * 3000
    root = bytearray(ROOTSECT * SECT)
    clus = 2
    for i, path in enumerate(files):
        data = open(path, 'rb').read()
        n = max(1, (len(data) + SECT - 1) // SECT) if data else 0
        first = clus if n else 0
        for k in range(n):
            off = (DATA0 + clus - 2) * SECT
            chunk = data[k * SECT:(k + 1) * SECT]
            img[off:off + len(chunk)] = chunk
            fat[clus] = clus + 1 if k < n - 1 else 0xFFF
            clus += 1
        e = bytearray(32)
        e[0:11] = short_name(path)
        e[11] = 0x20
        struct.pack_into('<HH', e, 22, 0x6000, (2026 - 1980) << 9 | 10 << 5 | 3)
        struct.pack_into('<HI', e, 26, first, len(data))
        root[i * 32:(i + 1) * 32] = e
    assert clus - 2 <= TOTAL - DATA0, 'floppy full'
    fatb = bytearray(SPF * SECT)
    for c in range(0, len(fat) - 1, 2):
        a, b = fat[c], fat[c + 1]
        o = c * 3 // 2
        if o + 3 > len(fatb):
            break
        fatb[o] = a & 0xFF
        fatb[o + 1] = (a >> 8) | ((b & 0xF) << 4)
        fatb[o + 2] = b >> 4
    for f in range(NFATS):
        o = (RSVD + f * SPF) * SECT
        img[o:o + len(fatb)] = fatb
    o = (RSVD + NFATS * SPF) * SECT
    img[o:o + len(root)] = root
    open(out, 'wb').write(img)


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2:])
