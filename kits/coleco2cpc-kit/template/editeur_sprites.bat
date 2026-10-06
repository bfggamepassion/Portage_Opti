@echo off
rem Éditeur des sprites en mode 0 (ouvre le navigateur). Fermer cette fenêtre pour l'arrêter.
cd /d "%~dp0"
python tools\sprite_editor.py
pause
