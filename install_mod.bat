@echo off
setlocal enabledelayedexpansion
title Instalador do Mod AI Tuner - BeamNG.drive

echo ========================================================
echo       INSTALADOR AUTOMATICO: BEAMNG.DRIVE AI TUNER
echo ========================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SOURCE_MOD=%SCRIPT_DIR%beamng_mod\ai_tuner"

if not exist "%SOURCE_MOD%" (
    echo [ERRO] Pasta de origem do mod nao encontrada em:
    echo "%SOURCE_MOD%"
    pause
    exit /b 1
)

set "TARGET_DIR="

:: 1. Verificar ficheiro de configuracao BeamNG.drive.ini (se existir pasta personalizada)
if exist "%LOCALAPPDATA%\BeamNG\BeamNG.drive.ini" (
    for /f "tokens=1,2 delims==" %%A in ('type "%LOCALAPPDATA%\BeamNG\BeamNG.drive.ini"') do (
        set "KEY=%%A"
        set "VAL=%%B"
        set "KEY=!KEY: =!"
        if /i "!KEY!"=="userFolder" (
            set "TARGET_DIR=!VAL:~1!"
            set "TARGET_DIR=!TARGET_DIR: =!"
            if exist "!TARGET_DIR!\current\mods" (
                set "TARGET_DIR=!TARGET_DIR!\current"
            )
        )
    )
)

:: 2. Se nao encontrou no ini, procurar na directoria padrao %LOCALAPPDATA%\BeamNG.drive\
if "!TARGET_DIR!"=="" (
    for /d %%D in ("%LOCALAPPDATA%\BeamNG.drive\0.*") do (
        set "TARGET_DIR=%%D"
    )
)

:: 3. Se ainda assim nao encontrou, usar o caminho standard
if "!TARGET_DIR!"=="" (
    set "TARGET_DIR=%LOCALAPPDATA%\BeamNG.drive\current"
)

echo Directoria de utilizador do BeamNG detectada:
echo "!TARGET_DIR!"
echo.

set "DEST_UNPACKED=!TARGET_DIR!\mods\unpacked\ai_tuner"
set "DEST_ZIP=!TARGET_DIR!\mods\ai_tuner.zip"

echo Criando pasta do mod em:
echo "!DEST_UNPACKED!"
echo.

if not exist "!DEST_UNPACKED!" (
    mkdir "!DEST_UNPACKED!" 2>nul
)

echo Copiando ficheiros do mod...
xcopy /E /I /Y /Q "%SOURCE_MOD%\*" "!DEST_UNPACKED!\"

echo Gerando pacote ai_tuner.zip para o Gestor de Mods...
powershell -Command "Compress-Archive -Path '%SOURCE_MOD%\*' -DestinationPath '!DEST_ZIP!' -Force" 2>nul

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo      [SUCESSO] Mod AI Tuner instalado com exito!
    echo ========================================================
    echo.
    echo Localizacao instalada:
    echo "!DEST_UNPACKED!"
    echo.
    echo PASSOS SEGUINTES:
    echo 1. Inicia o backend Python executando:
    echo    "%SCRIPT_DIR%backend\run_backend.bat"
    echo.
    echo 2. Abre o BeamNG.drive, carrega qualquer mapa e carro.
    echo.
    echo 3. Pressiona ESC :: UI Apps [Menu Lateral] :: Adicionar App [+].
    echo    Procura por "AI Dyno Tuner" e adiciona ao teu ecra!
    echo.
) else (
    echo.
    echo [ERRO] Ocorreu uma falha ao copiar os ficheiros.
    echo Podes copiar manualmente a pasta 'beamng_mod\ai_tuner' para:
    echo "!TARGET_DIR!\mods\unpacked\ai_tuner"
    echo.
)

pause
