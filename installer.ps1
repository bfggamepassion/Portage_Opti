# Installe les skills de portage/optimisation dans Claude Code et vérifie la chaîne d'outils.
#   powershell -ExecutionPolicy Bypass -File installer.ps1            # installe + vérifie
#   powershell -ExecutionPolicy Bypass -File installer.ps1 -Verifier  # vérifie seulement
param([switch]$Verifier)

$Depot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Skills = Join-Path $env:USERPROFILE ".claude\skills"
$L      = $env:LOCALAPPDATA

if (-not $Verifier) {
    New-Item -ItemType Directory -Force $Skills | Out-Null
    Get-ChildItem (Join-Path $Depot "skills") -Directory | ForEach-Object {
        $dst = Join-Path $Skills $_.Name
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst -Confirm:$false }
        Copy-Item -Recurse $_.FullName $dst
        # <DEPOT> dans les SKILL.md -> chemin réel de ce dépôt
        Get-ChildItem $dst -Recurse -Filter *.md | ForEach-Object {
            $t = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
            if ($t.Contains("<DEPOT>")) {
                [IO.File]::WriteAllText($_.FullName, $t.Replace("<DEPOT>", $Depot), (New-Object Text.UTF8Encoding $false))
            }
        }
        Write-Host "skill installée : $($_.Name)"
    }
}

Write-Host "`n== Chaîne d'outils (chemins attendus par les scripts des projets) =="
$outils = [ordered]@{
    "sjasmplus 1.24 (Z80)"        = "$L\sjasmplus\sjasmplus-1.24.0.win\sjasmplus.exe"
    "64tass 1.60 (6502)"          = "$L\64tass\64tass-1.60.3243\64tass.exe"
    "asm6809 2.17 (6809)"         = "$L\asm6809\asm6809-2.17-w64\asm6809.exe"
    "RGBDS (Game Boy)"            = "$L\rgbds\rgbasm.exe"
    "Caprice32 (CPC)"             = "$L\Caprice32\cap32-win64\cap32.exe"
    "VICE 3.10 x64sc (C64)"       = "$L\VICE\GTK3VICE-3.10-win64\bin\x64sc.exe"
    "VICE 3.10 c1541"             = "$L\VICE\GTK3VICE-3.10-win64\bin\c1541.exe"
    "openMSX (MSX, Coleco)"       = "$L\openMSX\openmsx.exe"
    "BIOS Coleco pour openMSX"    = "$([Environment]::GetFolderPath('MyDocuments'))\openMSX\share\systemroms\COLECO.ROM"
    "DCMOTO (Thomson MO5)"        = "$L\dcmoto\dcmoto-64\dcmoto.exe"
    "ZEsarUX 13 (ZX Spectrum)"    = "$L\ZEsarUX\ZEsarUX_windows-13.0\zesarux.exe"
    "Mesen2 (GB, SMS)"            = "$L\Mesen2\Mesen.exe"
}
foreach ($k in $outils.Keys) {
    $ok = Test-Path $outils[$k]
    $etat = "MANQUE"; if ($ok) { $etat = "ok" }
    Write-Host ("{0,-7} {1,-28} {2}" -f $etat, $k, $outils[$k])
}
foreach ($c in "python", "git", "sh", "node") {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    $etat = "MANQUE"; $p = ""
    if ($cmd) { $etat = "ok"; $p = $cmd.Source }
    elseif ($c -eq "sh" -and (Test-Path "$env:ProgramFiles\Git\bin\sh.exe")) { $etat = "ok"; $p = "$env:ProgramFiles\Git\bin\sh.exe (Git Bash)" }
    Write-Host ("{0,-7} {1,-28} {2}" -f $etat, $c, $p)
}

Write-Host "`n== Paquets Python =="
python -c "import importlib.util as u; [print(('ok     ' if u.find_spec(m) else 'MANQUE ') + m) for m in ['PIL','numpy','py65','pygame','capstone','z80dis','skoolkit','customtkinter']]"
Write-Host "`nPaquets manquants : python -m pip install -r requirements.txt"
Write-Host "Détails et liens de téléchargement : INSTALLATION.md"
