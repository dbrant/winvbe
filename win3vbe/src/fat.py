"""Minimal FAT12/16 reader/writer for a partitioned raw disk image."""
import struct, sys, os

class FAT:
    def __init__(self, path, writable=False):
        self.f = open(path, 'r+b' if writable else 'rb')
        mbr = self.read_abs(0, 512)
        self.part_lba = struct.unpack('<I', mbr[446+8:446+12])[0]
        bs = self.read_abs(self.part_lba * 512, 512)
        self.bps, self.spc, self.rsvd, self.nfats, self.nroot, ts16, media, self.spf = \
            struct.unpack('<HBHBHHBH', bs[11:24])
        ts32 = struct.unpack('<I', bs[32:36])[0]
        self.total = ts16 or ts32
        self.fat_off = (self.part_lba + self.rsvd) * self.bps
        self.root_off = self.fat_off + self.nfats * self.spf * self.bps
        self.data_off = self.root_off + self.nroot * 32
        self.csize = self.spc * self.bps
        nclus = (self.total - self.rsvd - self.nfats*self.spf - (self.nroot*32 + self.bps-1)//self.bps) // self.spc
        self.nclus = nclus
        self.fat16 = nclus >= 4085
        self.fat = bytearray(self.read_abs(self.fat_off, self.spf * self.bps))

    def read_abs(self, off, n):
        self.f.seek(off); return self.f.read(n)

    def write_abs(self, off, data):
        self.f.seek(off); self.f.write(data)

    def next_clus(self, c):
        if self.fat16:
            return struct.unpack('<H', self.fat[c*2:c*2+2])[0]
        v = struct.unpack('<H', self.fat[c*3//2:c*3//2+2])[0]
        return (v >> 4) if c & 1 else (v & 0xfff)

    def set_clus(self, c, v):
        if self.fat16:
            self.fat[c*2:c*2+2] = struct.pack('<H', v)
        else:
            raise NotImplementedError

    def eoc(self, c):
        return c >= (0xFFF8 if self.fat16 else 0xFF8)

    def chain(self, c):
        out = []
        while c >= 2 and not self.eoc(c):
            out.append(c); c = self.next_clus(c)
        return out

    def clus_off(self, c):
        return self.data_off + (c - 2) * self.csize

    def read_chain(self, c):
        return b''.join(self.read_abs(self.clus_off(x), self.csize) for x in self.chain(c))

    def dir_entries(self, clus):
        """returns list of (name, attr, clus, size, raw_offset)"""
        if clus == 0:
            data = self.read_abs(self.root_off, self.nroot * 32)
            offs = [self.root_off + i*32 for i in range(self.nroot)]
        else:
            data = b''; offs = []
            for x in self.chain(clus):
                data += self.read_abs(self.clus_off(x), self.csize)
                offs += [self.clus_off(x) + i*32 for i in range(self.csize//32)]
        res = []
        for i in range(len(data)//32):
            e = data[i*32:i*32+32]
            if e[0] == 0: break
            if e[0] == 0xE5 or e[11] == 0x0F: continue
            name = e[0:8].decode('latin1').rstrip()
            ext = e[8:11].decode('latin1').rstrip()
            full = name + ('.' + ext if ext else '')
            res.append((full, e[11], struct.unpack('<H', e[26:28])[0], struct.unpack('<I', e[28:32])[0], offs[i]))
        return res

    def find(self, path):
        parts = [p for p in path.replace('\\', '/').split('/') if p]
        clus = 0; ent = None
        for p in parts:
            for e in self.dir_entries(clus):
                if e[0].upper() == p.upper():
                    ent = e; clus = e[2]; break
            else:
                return None
        return ent

    def read_file(self, path):
        e = self.find(path)
        if e is None: raise FileNotFoundError(path)
        return self.read_chain(e[2])[:e[3]]

    def walk(self, clus=0, prefix=''):
        for e in self.dir_entries(clus):
            if e[0] in ('.', '..'): continue
            p = prefix + '/' + e[0]
            yield p, e
            if e[1] & 0x10:
                yield from self.walk(e[2], p)

    def free_clusters(self):
        return [c for c in range(2, self.nclus + 2) if self.next_clus(c) == 0]

    def flush_fat(self):
        for i in range(self.nfats):
            self.write_abs(self.fat_off + i * self.spf * self.bps, bytes(self.fat))

    def write_file(self, path, data):
        """Create or replace a file in an existing directory."""
        parts = [p for p in path.replace('\\', '/').split('/') if p]
        dirpath, fname = parts[:-1], parts[-1].upper()
        dclus = 0
        if dirpath:
            de = self.find('/'.join(dirpath)); dclus = de[2]
        existing = None
        for e in self.dir_entries(dclus):
            if e[0].upper() == fname: existing = e
        # free old chain
        if existing and existing[2] >= 2:
            for c in self.chain(existing[2]): self.set_clus(c, 0)
        need = (len(data) + self.csize - 1) // self.csize
        free = self.free_clusters()[:need]
        if len(free) < need: raise IOError('disk full')
        for i, c in enumerate(free):
            self.set_clus(c, free[i+1] if i+1 < len(free) else 0xFFFF)
            chunk = data[i*self.csize:(i+1)*self.csize]
            self.write_abs(self.clus_off(c), chunk.ljust(self.csize, b'\0'))
        first = free[0] if free else 0
        name, _, ext = fname.partition('.')
        raw_name = name.ljust(8).encode('latin1') + ext.ljust(3).encode('latin1')
        if existing:
            off = existing[4]
            ent = bytearray(self.read_abs(off, 32))
            ent[26:28] = struct.pack('<H', first); ent[28:32] = struct.pack('<I', len(data))
            self.write_abs(off, bytes(ent))
        else:
            off = self._free_dirent(dclus)
            ent = bytearray(32)
            ent[0:11] = raw_name; ent[11] = 0x20
            ent[22:24] = struct.pack('<H', 0x6000); ent[24:26] = struct.pack('<H', (2026-1980) << 9 | 10 << 5 | 3)
            ent[26:28] = struct.pack('<H', first); ent[28:32] = struct.pack('<I', len(data))
            self.write_abs(off, bytes(ent))
        self.flush_fat()

    def _free_dirent(self, dclus):
        if dclus == 0:
            offs = [self.root_off + i*32 for i in range(self.nroot)]
        else:
            offs = []
            for x in self.chain(dclus):
                offs += [self.clus_off(x) + i*32 for i in range(self.csize//32)]
        for off in offs:
            b = self.read_abs(off, 1)
            if b[0] in (0, 0xE5): return off
        raise IOError('directory full')

    def mkdir(self, path):
        parts = [p for p in path.replace('\\', '/').split('/') if p]
        dclus = 0
        if parts[:-1]:
            dclus = self.find('/'.join(parts[:-1]))[2]
        c = self.free_clusters()[0]
        self.set_clus(c, 0xFFFF)
        blk = bytearray(self.csize)
        def mk(n, cl):
            e = bytearray(32); e[0:11] = n; e[11] = 0x10; e[26:28] = struct.pack('<H', cl); return e
        blk[0:32] = mk(b'.          ', c); blk[32:64] = mk(b'..         ', dclus)
        self.write_abs(self.clus_off(c), bytes(blk))
        off = self._free_dirent(dclus)
        name = parts[-1].upper().ljust(11).encode('latin1')
        self.write_abs(off, bytes(mk(name, c)))
        self.flush_fat()

if __name__ == '__main__':
    cmd = sys.argv[1]; img = sys.argv[2]
    if cmd == 'ls':
        fs = FAT(img)
        for p, e in fs.walk():
            print(f"{p:40s} {'<DIR>' if e[1]&0x10 else e[3]:>8}")
    elif cmd == 'get':
        fs = FAT(img)
        for p in sys.argv[3:-1]:
            data = fs.read_file(p)
            open(os.path.join(sys.argv[-1], os.path.basename(p)), 'wb').write(data)
    elif cmd == 'put':
        fs = FAT(img, writable=True)
        fs.write_file(sys.argv[4], open(sys.argv[3], 'rb').read())
