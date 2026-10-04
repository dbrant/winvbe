"""NE (16-bit Windows) executable parser."""
import struct, sys

class NE:
    def __init__(self, data):
        self.d = d = data
        self.ne = ne = struct.unpack('<H', d[0x3c:0x3e])[0]
        assert d[ne:ne+2] == b'NE', 'not NE'
        h = struct.unpack('<2sBBHHIHHHHHHHHHHHHHHHHIHHHBB', d[ne:ne+0x40][:struct.calcsize('<2sBBHHIHHHHHHHHHHHHHHHHIHHHBB')])
        (sig, self.linkver, self.linkrev, self.entoff, self.entlen, self.crc, self.flags, self.autodata,
         self.heap, self.stack, self.ip, self.cs, self.sp, self.ss, self.nseg, self.nmod, self.nresnamlen,
         self.segoff, self.rsrcoff, self.resnamoff, self.modoff, self.impoff, self.nresnamoff,
         self.nmovent, self.align, self.nrsrc, self.exetype, self.flags2) = h
        # cs:ip packed as dword: low word ip, high word cs
        self.shift = self.align or 9
        self.expver = struct.unpack('<H', d[ne+0x3e:ne+0x40])[0]
        self.segs = []
        for i in range(self.nseg):
            o = ne + self.segoff + i*8
            sec, length, flg, minalloc = struct.unpack('<HHHH', d[o:o+8])
            self.segs.append(dict(sector=sec, len=length or (0x10000 if sec else 0), flags=flg, minalloc=minalloc or 0x10000,
                                  off=sec << self.shift))
        self.modrefs = []
        for i in range(self.nmod):
            o = struct.unpack('<H', d[ne+self.modoff+i*2:ne+self.modoff+i*2+2])[0]
            self.modrefs.append(self.pstr(ne + self.impoff + o))
        self.resnames = self.names(ne + self.resnamoff)
        self.nresnames = self.names(self.nresnamoff) if self.nresnamoff else []
        self.entries = self.parse_entries()

    def pstr(self, o):
        n = self.d[o]; return self.d[o+1:o+1+n].decode('latin1')

    def names(self, o):
        out = []
        while self.d[o]:
            n = self.d[o]; s = self.d[o+1:o+1+n].decode('latin1')
            ordn = struct.unpack('<H', self.d[o+1+n:o+3+n])[0]
            out.append((s, ordn)); o += 3 + n
        return out

    def parse_entries(self):
        d = self.d; o = self.ne + self.entoff; end = o + self.entlen
        ents = {}; ordn = 1
        while o < end:
            cnt = d[o]; ind = d[o+1]; o += 2
            if cnt == 0: break
            for i in range(cnt):
                if ind == 0:
                    pass
                elif ind == 0xFF:
                    flg = d[o]; seg = d[o+3]; off = struct.unpack('<H', d[o+4:o+6])[0]
                    ents[ordn] = (seg, off, flg); o += 6
                else:
                    flg = d[o]; off = struct.unpack('<H', d[o+1:o+3])[0]
                    ents[ordn] = (ind, off, flg); o += 3
                ordn += 1
        return ents

    def seg_data(self, i):
        s = self.segs[i]
        if s['sector'] == 0: return b''
        return self.d[s['off']:s['off']+s['len']]

    def relocs(self, i):
        s = self.segs[i]
        if not (s['flags'] & 0x100): return []
        o = s['off'] + s['len']
        n = struct.unpack('<H', self.d[o:o+2])[0]; o += 2
        out = []
        for k in range(n):
            atype, rtype, off, a, b = struct.unpack('<BBHHH', self.d[o:o+8]); o += 8
            out.append(dict(atype=atype, rtype=rtype, off=off, a=a, b=b))
        return out

if __name__ == '__main__':
    ne = NE(open(sys.argv[1], 'rb').read())
    print('linkver', ne.linkver, ne.linkrev, 'flags %04x' % ne.flags, 'autodata', ne.autodata, 'heap', ne.heap, 'stack', ne.stack,
          'exetype', ne.exetype, 'expver %04x' % ne.expver, 'align', ne.align)
    print('modrefs', ne.modrefs)
    print('resnames', ne.resnames)
    print('nresnames', ne.nresnames)
    for i, s in enumerate(ne.segs):
        print('seg', i+1, {k: (hex(v) if isinstance(v, int) else v) for k, v in s.items()}, 'nrel', len(ne.relocs(i)))
    for k, v in sorted(ne.entries.items()):
        print('entry', k, v)

def parse_resources(ne):
    d = ne.d; o = ne.ne + ne.rsrcoff
    if ne.rsrcoff == ne.resnamoff: return []
    shift = struct.unpack('<H', d[o:o+2])[0]; o += 2
    out = []
    while True:
        tid = struct.unpack('<H', d[o:o+2])[0]
        if tid == 0: break
        cnt = struct.unpack('<H', d[o+2:o+4])[0]; o += 8
        for i in range(cnt):
            off, ln, fl, rid, h, u = struct.unpack('<HHHHHH', d[o:o+12]); o += 12
            out.append(dict(type=tid, id=rid, flags=fl, off=off << shift, len=ln << shift))
    return out
