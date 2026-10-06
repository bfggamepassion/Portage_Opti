"""Cassette MO5 (.k7) contenant un fichier binaire (chargé par LOADM).

Format des blocs du MO5 (cf. MAME, src/lib/formats/thom_cas.cpp) :
  octets $01 de synchronisation, puis $3C $5A, type (0 : en-tête,
  1 : données, $FF : fin), taille (= octets de données + 2), données,
  somme de contrôle (somme des données + somme = 0 modulo 256).
En-tête : nom (8 caractères), extension (3), type de fichier (2 : binaire),
mode (0), 0.
Le contenu est le fichier binaire tel que l'écrit asm6809 -C (segments
$00 longueur adresse données..., puis $FF $00 $00 adresse de lancement),
qui est aussi le format de LOADM.
Usage : make_k7.py binaire.lm sortie.k7 NOM
"""
import sys

LEADER = 16


def block(kind, data):
    assert len(data) <= 254
    crc = (-sum(data)) & 0xFF
    return bytes([1] * LEADER) + bytes([0x3C, 0x5A, kind, (len(data) + 2) & 0xFF]) + bytes(data) + bytes([crc])


def main():
    src, out, name = sys.argv[1], sys.argv[2], sys.argv[3].upper()
    payload = open(src, 'rb').read()
    head = name.ljust(8)[:8].encode('ascii') + b'BIN' + bytes([2, 0, 0])
    k7 = bytearray(block(0, head))
    for k in range(0, len(payload), 254):
        k7 += block(1, payload[k:k + 254])
    k7 += block(0xFF, b'')
    open(out, 'wb').write(k7)
    print(f'{out} : {len(payload)} octets en {(len(payload) + 253) // 254} blocs')


if __name__ == '__main__':
    main()
