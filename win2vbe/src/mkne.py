"""Build a Windows 2.x display driver NE file from a NASM flat binary.

Layout of the NASM output: CODE (CODE_SIZE bytes) followed by DATA (DATA_SIZE bytes).
The code segment starts with a table of 3-byte near jumps, one per entry in EXPORTS
(in that order), so every export lives at offset 3*index.
"""
import struct, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.dirname(HERE))
from ne import NE

ALIGN = 4  # sector shift (16-byte sectors), same as the original driver

# (name, ordinal) in jump-table order. Index 0 is the library init entry (not exported).
EXPORTS = [
    ('LIBINIT', None),
    ('BITBLT', 1), ('COLORINFO', 2), ('CONTROL', 3), ('DISABLE', 4), ('ENABLE', 5),
    ('ENUMDFONTS', 6), ('ENUMOBJ', 7), ('OUTPUT', 8), ('PIXEL', 9), ('REALIZEOBJECT', 10),
    ('STRBLT', 11), ('SCANLR', 12), ('DEVICEMODE', 13), ('EXTTEXTOUT', 14),
    ('GETCHARWIDTH', 15), ('DEVICEBITMAP', 16), ('FASTBORDER', 17), ('SETATTRIBUTE', 18),
    ('DO_POLYLINES', 90), ('DO_SCANLINES', 91),
    ('INQUIRE', 101), ('SETCURSOR', 102), ('MOVECURSOR', 103), ('CHECKCURSOR', 104),
]


def pstr(s):
    b = s.encode('latin1')
    return bytes([len(b)]) + b


def build(binfile, outfile, code_size, data_size, description, template):
    raw = open(binfile, 'rb').read()
    assert len(raw) == code_size + data_size, (len(raw), code_size, data_size)
    code, data = raw[:code_size], raw[code_size:]

    tpl = open(template, 'rb').read()
    tne = NE(tpl)
    stub = bytearray(tpl[:0x400])          # MZ stub, e_lfanew = 0x400

    # --- resource table: copy verbatim, relocate data offsets later
    rs_start = tne.ne + tne.rsrcoff
    rs_end = tne.ne + tne.resnamoff
    rsrc = bytearray(tpl[rs_start:rs_end])
    shift = struct.unpack('<H', rsrc[0:2])[0]
    res_items = []  # (offset in rsrc of the entry, data bytes)
    o = 2
    while True:
        tid = struct.unpack('<H', rsrc[o:o+2])[0]
        if tid == 0: break
        cnt = struct.unpack('<H', rsrc[o+2:o+4])[0]; o += 8
        for _ in range(cnt):
            off, ln = struct.unpack('<HH', rsrc[o:o+4])
            res_items.append((o, tpl[off << shift:(off << shift) + (ln << shift)]))
            o += 12

    resnames = pstr('DISPLAY') + b'\0\0' + b'\0'
    modref = b''
    impnames = b'\0'

    # --- entry table
    ords = {o: i for i, (n, o) in enumerate(EXPORTS) if o}
    entry = bytearray()
    ordn = 1
    maxord = max(ords)
    while ordn <= maxord:
        if ordn not in ords:
            k = 0
            while ordn + k <= maxord and (ordn + k) not in ords and k < 255: k += 1
            entry += bytes([k, 0]); ordn += k; continue
        run = []
        while ordn in ords and len(run) < 255:
            run.append(ords[ordn]); ordn += 1
        entry += bytes([len(run), 1])
        for idx in run:
            entry += bytes([1]) + struct.pack('<H', idx * 3)   # flags: exported
    entry += b'\0'

    nonres = pstr(description) + b'\0\0'
    for n, o in EXPORTS:
        if o: nonres += pstr(n) + struct.pack('<H', o)
    nonres += b'\0'

    # --- header layout (offsets relative to NE header)
    hdr_len = 0x40
    segtab_off = hdr_len
    nseg = 2
    rsrc_off = segtab_off + 8 * nseg
    resn_off = rsrc_off + len(rsrc)
    mod_off = resn_off + len(resnames)
    imp_off = mod_off + len(modref)
    ent_off = imp_off + len(impnames)
    tables_end = ent_off + len(entry)
    nonres_file = 0x400 + tables_end

    def sector_align(pos):
        a = 1 << ALIGN
        return (pos + a - 1) & ~(a - 1)

    pos = sector_align(nonres_file + len(nonres))
    code_pos = pos; pos = sector_align(pos + len(code))
    data_pos = pos; pos = sector_align(pos + len(data))
    # resources
    res_pos = []
    for (eo, rd) in res_items:
        a = 1 << shift
        pos = (pos + a - 1) & ~(a - 1)
        res_pos.append(pos)
        pos += len(rd)
    total = pos

    for (eo, rd), rp in zip(res_items, res_pos):
        struct.pack_into('<HH', rsrc, eo, rp >> shift, (len(rd) + (1 << shift) - 1) >> shift)

    segtab = struct.pack('<HHHH', code_pos >> ALIGN, len(code) & 0xFFFF, 0x0C60, len(code) & 0xFFFF)
    segtab += struct.pack('<HHHH', data_pos >> ALIGN, len(data) & 0xFFFF, 0x0C61, len(data) & 0xFFFF)

    h = bytearray(0x40)
    h[0:2] = b'NE'; h[2] = 5; h[3] = 1
    struct.pack_into('<HH', h, 0x04, ent_off, len(entry))
    struct.pack_into('<I', h, 0x08, 0)
    struct.pack_into('<HH', h, 0x0C, 0x8001, 2)       # flags: library + single data; autodata seg 2
    struct.pack_into('<HH', h, 0x10, 0, 0)            # heap, stack
    struct.pack_into('<HH', h, 0x14, 0, 1)            # CS:IP = 1:0000 (LIBINIT)
    struct.pack_into('<HH', h, 0x18, 0, 0)            # SS:SP
    struct.pack_into('<HHH', h, 0x1C, nseg, 0, len(nonres))
    struct.pack_into('<HHHHH', h, 0x22, segtab_off, rsrc_off, resn_off, mod_off, imp_off)
    struct.pack_into('<I', h, 0x2C, nonres_file)
    struct.pack_into('<HHH', h, 0x30, 0, ALIGN, 0)
    h[0x36] = 0; h[0x37] = 0
    struct.pack_into('<H', h, 0x3E, 0x0201)

    out = bytearray(total)
    out[0:0x400] = stub
    out[0x400:0x400 + 0x40] = h
    t = segtab + bytes(rsrc) + resnames + modref + impnames + bytes(entry)
    out[0x440:0x440 + len(t)] = t
    out[nonres_file:nonres_file + len(nonres)] = nonres
    out[code_pos:code_pos + len(code)] = code
    out[data_pos:data_pos + len(data)] = data
    for (eo, rd), rp in zip(res_items, res_pos):
        out[rp:rp + len(rd)] = rd
    open(outfile, 'wb').write(out)
    return out


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('bin'); ap.add_argument('out')
    ap.add_argument('--code', type=lambda x: int(x, 0), required=True)
    ap.add_argument('--data', type=lambda x: int(x, 0), required=True)
    ap.add_argument('--desc', required=True)
    ap.add_argument('--template', required=True)
    a = ap.parse_args()
    build(a.bin, a.out, a.code, a.data, a.desc, a.template)
