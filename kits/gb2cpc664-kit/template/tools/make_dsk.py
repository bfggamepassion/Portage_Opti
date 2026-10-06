"""Image disquette Amstrad CPC (.dsk, format « Extended », format DATA).

  python tools/make_dsk.py sortie.dsk NOM.EXT fichier.bin chargement exécution

Le binaire reçoit un en-tête AMSDOS (type 2 = binaire, adresse de chargement,
adresse d'exécution) : RUN"NOM" le charge et le lance.

Format DATA : 40 pistes, 1 face, 9 secteurs de 512 octets (&C1-&C9) par
piste ; blocs de 1 Ko ; catalogue = 4 premiers secteurs (64 entrées de 32
octets), blocs 0 et 1 ; une entrée par tranche de 16 Ko (extent).
"""
import sys

TRACKS, SECTORS, SECSIZE = 40, 9, 512
FIRST_ID = 0xC1


def amsdos_header(name, ext, data, load, entry):
    h = bytearray(128)
    h[1:9] = name.ljust(8).encode('ascii')[:8]
    h[9:12] = ext.ljust(3).encode('ascii')[:3]
    h[18] = 2                                   # binaire
    h[21:23] = load.to_bytes(2, 'little')
    h[24:26] = len(data).to_bytes(2, 'little')
    h[26:28] = entry.to_bytes(2, 'little')
    h[64:67] = len(data).to_bytes(3, 'little')
    h[67:69] = (sum(h[:67]) & 0xFFFF).to_bytes(2, 'little')
    return bytes(h)


def build(files):
    """files : liste de (nom, ext, contenu avec en-tête)."""
    disk = bytearray([0xE5]) * (TRACKS * SECTORS * SECSIZE)
    directory = bytearray([0xE5]) * 2048
    block = 2                                   # blocs 0-1 : catalogue
    entry = 0
    for name, ext, content in files:
        nblocks = (len(content) + 1023) // 1024
        blocks = list(range(block, block + nblocks))
        for k in range(nblocks):
            disk[(block + k) * 1024:(block + k) * 1024 + 1024] = \
                content[k * 1024:(k + 1) * 1024].ljust(1024, b'\x1a')
        block += nblocks
        records = (len(content) + 127) // 128
        for ex in range(0, max(1, (nblocks + 15) // 16)):
            e = bytearray(32)
            e[0] = 0
            e[1:9] = name.ljust(8).encode('ascii')[:8]
            e[9:12] = ext.ljust(3).encode('ascii')[:3]
            e[12] = ex
            rc = min(128, records - ex * 128)
            e[15] = rc
            for i, b in enumerate(blocks[ex * 16:(ex + 1) * 16]):
                e[16 + i] = b
            directory[entry * 32:(entry + 1) * 32] = e
            entry += 1
    disk[0:2048] = directory
    if block * 1024 > len(disk):
        sys.exit('disquette pleine')
    # image « EXTENDED CPC DSK »
    out = bytearray(256)
    out[0:34] = b'EXTENDED CPC DSK File\r\nDisk-Info\r\n'
    out[34:48] = b'Tennis tools  '
    out[48] = TRACKS
    out[49] = 1
    tsize = 256 + SECTORS * SECSIZE
    for t in range(TRACKS):
        out[52 + t] = tsize // 256
    for t in range(TRACKS):
        ti = bytearray(256)
        ti[0:12] = b'Track-Info\r\n'
        ti[16] = t
        ti[17] = 0
        ti[20] = 2                              # 512 octets
        ti[21] = SECTORS
        ti[22] = 0x4E
        ti[23] = 0xE5
        for s in range(SECTORS):
            o = 24 + s * 8
            ti[o:o + 4] = bytes([t, 0, FIRST_ID + s, 2])
            ti[o + 6:o + 8] = SECSIZE.to_bytes(2, 'little')
        out += ti
        out += disk[t * SECTORS * SECSIZE:(t + 1) * SECTORS * SECSIZE]
    return bytes(out)


def main():
    dsk, fname, binfile, load, entry = sys.argv[1:6]
    name, _, ext = fname.upper().partition('.')
    data = open(binfile, 'rb').read()
    load, entry = int(load, 0), int(entry, 0)
    content = amsdos_header(name, ext or 'BIN', data, load, entry) + data
    open(dsk, 'wb').write(build([(name, ext or 'BIN', content)]))
    print(f'{dsk} : {name}.{ext or "BIN"} {len(data)} octets, chargé en ${load:04X}, lancé en ${entry:04X}')


if __name__ == '__main__':
    main()
