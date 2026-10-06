#!/usr/bin/env python3
"""Met à jour les kits et les skills d'optimisation de ce dépôt depuis leurs dossiers de travail.

Copie, en filtrant (pas de ROM, d'images disque, de builds, ni d'exemples propres à un jeu) :
  - les kits de portage (gb2*-kit, coleco2cpc-kit)        -> kits/
  - les skills c64-optimisation et cpc-optimisation       -> skills/
  - les explications d'optimisation pour débutant         -> docs/optimisation/
Les skills de portage (portage-retro, gb-to-*, coleco-to-cpc-port) sont maintenues ici même et ne sont
pas écrasées.

Usage :
  python outils/synchroniser.py            # copie
  python outils/synchroniser.py --dry-run  # affiche seulement les volumes
Variables : SOURCE (dossier des projets de travail), CLAUDE_HOME (défaut ~/.claude).
"""
import os
import re
import shutil
import sys
from pathlib import Path

DEPOT = Path(__file__).resolve().parent.parent
SOURCE = Path(os.environ.get("SOURCE", r"G:\Mon Drive\Coding"))
CLAUDE = Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude"))
DRY = "--dry-run" in sys.argv

KITS = {
    "Tennis/gb2zx-kit": "gb2zx-kit",
    "Tennis/gb2c64-kit": "gb2c64-kit",
    "Tennis/gb2cpc664-kit": "gb2cpc664-kit",
    "Tennis/gb2coleco-kit": "gb2coleco-kit",
    "Tennis/gb2msx-kit": "gb2msx-kit",
    "Tennis/gb2mo5-kit": "gb2mo5-kit",
    "Cabbage/coleco2cpc-kit": "coleco2cpc-kit",
}
SKILLS = {
    CLAUDE / "skills" / "c64-optimisation": "c64-optimisation",
    SOURCE / "OptiCPC" / "skills" / "cpc-optimisation": "cpc-optimisation",
}
DOCS = {
    "OptiCPC/TECHNIQUES_CPC_EXPLIQUEES.md": "TECHNIQUES_CPC_EXPLIQUEES.md",
    "Opti-C64/TECHNIQUES_C64_EXPLIQUEES.md": "TECHNIQUES_C64_EXPLIQUEES.md",
}

DOSSIERS_EXCLUS = {"build", "dist", "runs", "archives", "archive", "backups", "__pycache__", ".git",
                   "node_modules", "out", "logs", "examples", "claude"}
FICHIERS_EXCLUS = {"repomix-output.xml", "settings.local.json", "sprites_cpc.json"}
# Extensions copiées et taille maximale (octets) : sources, scripts, docs, images d'outils.
TEXTE = {".py": 2_000_000, ".asm": 3_000_000, ".s": 2_000_000, ".inc": 2_000_000, ".sh": 200_000,
         ".bat": 200_000, ".ps1": 200_000, ".lua": 200_000, ".js": 1_000_000, ".html": 1_000_000,
         ".css": 200_000, ".md": 2_000_000, ".txt": 300_000, ".json": 1_000_000, ".cfg": 200_000,
         ".ini": 200_000, ".bas": 300_000, ".png": 1_000_000}
NOMS_TOUJOURS = {"Makefile", "requirements.txt", ".gitignore", "LICENSE"}

REGLES = [(re.compile(a, re.I), b) for a, b in [
    (r"G:\\Mon Drive\\Coding\\Tennis\\(gb2\w+-kit)", r"<DEPOT>\\kits\\\1"),
    (r"G:\\Mon Drive\\Coding\\Cabbage\\coleco2cpc-kit", r"<DEPOT>\\kits\\coleco2cpc-kit"),
    (r"C:\\Users\\[^\\]+\\AppData\\Local", "%LOCALAPPDATA%"),
    (r"C:\\Users\\[^\\]+\\\.claude", r"%USERPROFILE%\\.claude"),
    (r"/c/Users/[^/]+/AppData/Local", "$LOCALAPPDATA"),
    (r"`ACCC1\.11-EN\.pdf` à la racine du dépôt OptiCPC", "`docs/references/ACCC1.11-EN.pdf` du dépôt Portage_Opti"),
    (r"Dans le dépôt OptiCPC : `ACCC1\.11-EN\.pdf` à la racine\.", "Dans le dépôt Portage_Opti : `docs/references/ACCC1.11-EN.pdf`."),
]]

def nettoyer_md(t):
    """Chemins de la machine d'origine -> chemins du dépôt ; lignes pointant vers les exemples retirés."""
    for rx, rep in REGLES:
        t = rx.sub(rep, t)
    t = "".join(l for l in t.splitlines(keepends=True) if "examples/tennis" not in l)
    t = re.sub(r"[^\n]*exemple Tennis[^\n]*\n+```(sh)?\n```\n?", "", t)
    return re.sub(r"Le code complet de ce portage est dans le repo `[^`]*`\. ", "", t)

stats = {}

def copier(src: Path, dst: Path, cle):
    stats[cle] = stats.get(cle, 0) + src.stat().st_size
    if DRY:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.suffix.lower() == ".md" or src.name == "port_config.py":
        try:
            dst.write_text(nettoyer_md(src.read_text(encoding="utf-8")), encoding="utf-8", newline="")
            return
        except UnicodeDecodeError:
            pass
    shutil.copy2(src, dst)

def garder(f: Path):
    if f.name in FICHIERS_EXCLUS:
        return False
    if f.name in NOMS_TOUJOURS:
        return True
    lim = TEXTE.get(f.suffix.lower())
    return lim is not None and f.stat().st_size <= lim

def copier_arbre(src: Path, dst: Path, cle):
    if not src.is_dir():
        print("absent :", src)
        return
    for racine, dirs, fichiers in os.walk(src):
        r = Path(racine)
        dirs[:] = [d for d in dirs if d not in DOSSIERS_EXCLUS]
        for nom in fichiers:
            f = r / nom
            if garder(f):
                copier(f, dst / r.relative_to(src) / nom, cle)

def main():
    for src, dst in KITS.items():
        copier_arbre(SOURCE / src, DEPOT / "kits" / dst, "kits")
    for src, dst in SKILLS.items():
        copier_arbre(src, DEPOT / "skills" / dst, "skills")
    for src, dst in DOCS.items():
        if (SOURCE / src).exists():
            copier(SOURCE / src, DEPOT / "docs" / "optimisation" / dst, "docs")
    for k, v in sorted(stats.items()):
        print(f"{v / 1e6:8.2f} Mo  {k}")
    print(f"{sum(stats.values()) / 1e6:8.2f} Mo  TOTAL" + ("  (dry-run)" if DRY else ""))

if __name__ == "__main__":
    main()
