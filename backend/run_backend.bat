@echo off
title BeamNG AI Tuner - Backend Server
cd /d "%~dp0"

echo ========================================================
echo        BEAMNG.DRIVE AI TUNER - BACKEND SERVER
echo ========================================================
echo.

python -m pip install -r requirements.txt
if %ERRORLEVEL% NEQ 0 (
    echo [AVISO] Falha ao instalar dependencias com python. Tentando py...
    py -m pip install -r requirements.txt
)

echo.
echo Iniciando servidor Flask na porta 5000...
echo Deixa esta janela aberta enquanto jogas BeamNG.drive!
echo.

python app.py
if %ERRORLEVEL% NEQ 0 (
    py app.py
)

pause
