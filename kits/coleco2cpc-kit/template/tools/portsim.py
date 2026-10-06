"""Aides communes aux outils de mesure : symboles, CPC ou ColecoVision
simulés arrêtés au début d'un niveau (port_config.level_pokes)."""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
sys.path.insert(0, HERE)
import cpcsim  # noqa: E402
import port_config as P  # noqa: E402


def symbols():
    sym = {}
    for line in open(os.path.join(ROOT, 'build', P.GAME + '.sym')):
        k, _, v = line.partition(': EQU ')
        if v:
            sym[k] = int(v, 16)
    return sym


def cpc_poke(c, addr, val):
    """Écrit dans la RAM Coleco ($6000-$63FF, banque 5 à $4000 en vue jeu)."""
    c.ram[5 * 0x4000 + addr - 0x4000] = val
    if c.map[1] == 5:
        c.mem[addr] = val


def cpc_peek(c, addr):
    """Lit la RAM Coleco (c.ram n'est à jour pour les banques visibles
    qu'après un changement de configuration : lire c.mem si possible)."""
    if c.map[1] == 5:
        return c.mem[addr]
    return c.ram[5 * 0x4000 + addr - 0x4000]


def cpc_ram(c, lo, hi):
    """Octets lo..hi-1 de la RAM Coleco."""
    if c.map[1] == 5:
        return bytes(c.mem[lo:hi])
    return bytes(c.ram[5 * 0x4000 + lo - 0x4000:5 * 0x4000 + hi - 0x4000])


def cpc_level(n, extra_keys=''):
    """CPC simulé au niveau n (menu passé). Rend (cpc, touches)."""
    keys = cpcsim.parse_keys(P.START_KEYS_CPC + ' ' + extra_keys)
    c = cpcsim.CPC()
    c.run_frames(P.POKE_FRAME_CPC, keys)
    if n is not None:
        for a, v in P.level_pokes(n):
            cpc_poke(c, a, v)
    return c, keys


def cv_level(n, keys_after=lambda f: set()):
    """ColecoVision simulée (vrai BIOS) au niveau n."""
    import cvrun
    k, a, b = P.START_KEY_CV

    def keys(f):
        return ({k} if a <= f < b else set()) | keys_after(f)
    cv = cvrun.ColecoBios()
    cv.run_frames(P.POKE_FRAME_CV, keys)
    if n is not None:
        for addr, v in P.level_pokes(n):
            cv.mem[addr] = v
    return cv, keys
