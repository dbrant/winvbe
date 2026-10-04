"""NE linker for the Windows 3.0 VESA/VBE display driver.

Input is the NASM flat binary (CODE segment followed by DATA segment) plus the
NASM map file.  The map supplies:
  * export entry points: the symbols named in EXPORTS below;
  * relocation sites, marked by labels emitted by the macros in defs.inc:
      ..@__RF_<MODULE>_<ordinal>_<n>   far pointer to an imported function
      ..@__RW_<MODULE>_<ordinal>_<n>   16-bit imported constant (e.g. __A000H)
Resources (cursors, icons, system bitmaps, OEM data) are copied from the
stock VGA.DRV.
"""
import re, struct, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ne import NE

ALIGN = 4

# (symbol, ordinal, exported name)
EXPORTS = [
    ('BitBlt', 1, 'BITBLT'), ('ColorInfo', 2, 'COLORINFO'), ('Control', 3, 'CONTROL'),
    ('Disable', 4, 'DISABLE'), ('Enable', 5, 'ENABLE'), ('EnumDFonts', 6, 'ENUMDFONTS'),
    ('EnumObj', 7, 'ENUMOBJ'), ('Output', 8, 'OUTPUT'), ('Pixel', 9, 'PIXEL'),
    ('RealizeObject', 10, 'REALIZEOBJECT'), ('StrBlt', 11, 'STRBLT'), ('ScanLR', 12, 'SCANLR'),
    ('DeviceMode', 13, 'DEVICEMODE'), ('ExtTextOut', 14, 'EXTTEXTOUT'),
    ('GetCharWidth', 15, 'GETCHARWIDTH'), ('DeviceBitmap', 16, 'DEVICEBITMAP'),
    ('FastBorder', 17, 'FASTBORDER'), ('SetAttribute', 18, 'SETATTRIBUTE'),
    ('DeviceBitmapBits', 19, 'DEVICEBITMAPBITS'), ('CreateBitmap', 20, 'CREATEBITMAP'),
    ('DIBScreenBlt', 21, 'DIBSCREENBLT'),
    ('Output', 90, 'DO_POLYLINES'), ('Output', 91, 'DO_SCANLINES'),
    ('SaveScreenBitmap', 92, 'SAVESCREENBITMAP'),
    ('Inquire', 101, 'INQUIRE'), ('SetCursor', 102, 'SETCURSOR'),
    ('MoveCursor', 103, 'MOVECURSOR'), ('CheckCursor', 104, 'CHECKCURSOR'),
    ('UserRepaintDisable', 500, 'USERREPAINTDISABLE'),
]


def pstr(s):
    b = s.encode('latin1')
    return bytes([len(b)]) + b


def parse_map(path):
    """-> {section: {symbol: value}}"""
    secs = {}
    cur = None
    for line in open(path):
        m = re.match(r'---- Section (\S+) ', line)
        if m:
            cur = secs.setdefault(m.group(1), {})
            continue
        m = re.match(r'\s*([0-9A-F]+)\s+([0-9A-F]+)\s+(\S+)\s*$', line)
        if m and cur is not None:
            cur[m.group(3)] = int(m.group(2), 16)
    return secs


def build(binfile, mapfile, outfile, description, template):
    raw = open(binfile, 'rb').read()
    syms = parse_map(mapfile)
    code_syms, data_syms = syms['CODE'], syms.get('DATA', {})
    code_len = (code_syms['code_end'] + 15) & ~15
    code, data = raw[:code_len], raw[code_len:]

    # ---- relocations (code segment only)
    modules = []
    relocs = []
    for name, off in code_syms.items():
        m = re.match(r'\.\.@__R([FW])_([A-Z0-9]+)_(\d+)_\d+$', name)
        if not m:
            continue
        kind, mod, ordn = m.group(1), m.group(2), int(m.group(3))
        if mod not in modules:
            modules.append(mod)
        atype = 3 if kind == 'F' else 5
        relocs.append(struct.pack('<BBHHH', atype, 1, off, modules.index(mod) + 1, ordn))
    relocs.sort(key=lambda r: struct.unpack('<H', r[2:4])[0])
    code_reloc = struct.pack('<H', len(relocs)) + b''.join(relocs)

    tpl = open(template, 'rb').read()
    tne = NE(tpl)
    stub = bytearray(tpl[:tne.ne])
    struct.pack_into('<I', stub, 0x3C, 0x400 if len(stub) <= 0x400 else len(stub))
    stub = stub.ljust(0x400, b'\0')[:0x400]
    struct.pack_into('<I', stub, 0x3C, 0x400)

    # ---- resource table copied verbatim, data offsets fixed up later
    rsrc = bytearray(tpl[tne.ne + tne.rsrcoff:tne.ne + tne.resnamoff])
    shift = struct.unpack('<H', rsrc[0:2])[0]
    res_items = []
    o = 2
    while True:
        tid = struct.unpack('<H', rsrc[o:o+2])[0]
        if tid == 0:
            break
        cnt = struct.unpack('<H', rsrc[o+2:o+4])[0]
        o += 8
        for _ in range(cnt):
            off, ln = struct.unpack('<HH', rsrc[o:o+4])
            res_items.append((o, tpl[off << shift:(off << shift) + (ln << shift)]))
            o += 12

    resnames = pstr('DISPLAY') + b'\0\0' + b'\0'
    modref = b''
    impnames = b'\0'
    for mod in modules:
        modref += struct.pack('<H', len(impnames))
        impnames += pstr(mod)

    # ---- entry table: every export lives in fixed segment 1;
    # flag 3 = exported + uses the shared data segment (the loader patches the
    # "mov ax,ds / nop" prologue into "mov ax,DGROUP")
    ords = {o: code_syms[s] for s, o, n in EXPORTS}
    entry = bytearray()
    ordn = 1
    maxord = max(ords)
    while ordn <= maxord:
        if ordn not in ords:
            k = 0
            while ordn + k <= maxord and (ordn + k) not in ords and k < 255:
                k += 1
            entry += bytes([k, 0])
            ordn += k
            continue
        run = []
        while ordn in ords and len(run) < 255:
            run.append(ords[ordn])
            ordn += 1
        entry += bytes([len(run), 1])
        for off in run:
            entry += bytes([3]) + struct.pack('<H', off)
    entry += b'\0'

    nonres = pstr(description) + b'\0\0'
    for s, o, n in EXPORTS:
        nonres += pstr(n) + struct.pack('<H', o)
    nonres += b'\0'

    hdr_len = 0x40
    nseg = 2
    segtab_off = hdr_len
    rsrc_off = segtab_off + 8 * nseg
    resn_off = rsrc_off + len(rsrc)
    mod_off = resn_off + len(resnames)
    imp_off = mod_off + len(modref)
    ent_off = imp_off + len(impnames)
    tables_end = ent_off + len(entry)
    nonres_file = 0x400 + tables_end

    def align(pos, a=1 << ALIGN):
        return (pos + a - 1) & ~(a - 1)

    pos = align(nonres_file + len(nonres))
    code_pos = pos
    pos = align(pos + len(code) + len(code_reloc))
    data_pos = pos
    pos = align(pos + len(data))
    res_pos = []
    for (eo, rd) in res_items:
        pos = align(pos, 1 << shift)
        res_pos.append(pos)
        pos += len(rd)
    total = pos
    for (eo, rd), rp in zip(res_items, res_pos):
        struct.pack_into('<HH', rsrc, eo, rp >> shift, (len(rd) + (1 << shift) - 1) >> shift)

    cflags = 0x0D60 | (0x0100 if relocs else 0)        # fixed, pure, preload
    segtab = struct.pack('<HHHH', code_pos >> ALIGN, len(code), cflags, len(code))
    segtab += struct.pack('<HHHH', data_pos >> ALIGN, len(data), 0x0C61, len(data))

    h = bytearray(0x40)
    h[0:2] = b'NE'
    h[2], h[3] = 5, 1
    struct.pack_into('<HH', h, 0x04, ent_off, len(entry))
    struct.pack_into('<HH', h, 0x0C, 0x8301, 2)       # library, single data; autodata = seg 2
    struct.pack_into('<HH', h, 0x14, code_syms['LibInit'], 1)
    struct.pack_into('<HHH', h, 0x1C, nseg, len(modules), len(nonres))
    struct.pack_into('<HHHHH', h, 0x22, segtab_off, rsrc_off, resn_off, mod_off, imp_off)
    struct.pack_into('<I', h, 0x2C, nonres_file)
    struct.pack_into('<HHH', h, 0x30, 0, ALIGN, 0)
    h[0x36] = 2                                        # target OS: Windows
    struct.pack_into('<H', h, 0x3E, 0x0300)            # expected Windows version

    out = bytearray(total)
    out[0:0x400] = stub
    out[0x400:0x440] = h
    t = segtab + bytes(rsrc) + resnames + modref + impnames + bytes(entry)
    out[0x440:0x440 + len(t)] = t
    out[nonres_file:nonres_file + len(nonres)] = nonres
    out[code_pos:code_pos + len(code)] = code
    out[code_pos + len(code):code_pos + len(code) + len(code_reloc)] = code_reloc
    out[data_pos:data_pos + len(data)] = data
    for (eo, rd), rp in zip(res_items, res_pos):
        out[rp:rp + len(rd)] = rd
    open(outfile, 'wb').write(out)
    return len(code), len(data), len(relocs)


if __name__ == '__main__':
    print(build(*sys.argv[1:6]))
