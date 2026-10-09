@echo off
title Instalador de IA Local Gratuita - Ollama (BeamNG AI Tuner)
cd /d "%~dp0"

echo ========================================================
echo       INSTALACAO DE IA LOCAL GRATUITA (SEM PAGAR)
echo ========================================================
echo.
echo Esta ferramenta vai configurar o Ollama no teu PC.
echo - 100%% Gratuito e Ilimitado
echo - Roda diretamente na tua placa grafica (NVIDIA RTX)
echo - Sem chaves de API, sem registo, sem cartao de credito
echo.

:: Verificar se o Ollama ja esta instalado
where ollama >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] O Ollama ja se encontra instalado!
    goto PULL_MODEL
)

echo [1/2] A instalar o Ollama via Windows Package Manager (winget)...
winget install Ollama.Ollama --accept-package-agreements --accept-source-agreements

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [AVISO] O winget nao conseguiu instalar automaticamente.
    echo Podes fazer o download gratuito e manual em: https://ollama.com/download
    echo Depois de instalar, volta a executar este script!
    pause
    exit /b 1
)

echo.
echo [OK] Ollama instalado com sucesso!
echo.

:PULL_MODEL
echo [2/2] Descarregando o modelo 'llama3.2' (ultra-rapido e leve para jogos)...
echo O modelo tem cerca de 2 GB e ocupa muito pouca VRAM na tua GPU.
echo.

ollama pull llama3.2

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo      [SUCESSO] IA LOCAL CONFIGURADA COM SUCESSO!
    echo ========================================================
    echo.
    echo Modelo: llama3.2
    echo O Ollama esta pronto a responder aos teus pedidos no BeamNG!
    echo.
    echo Agora podes iniciar o backend:
    echo 1. Executa "backend\run_backend.bat"
    echo 2. Abre o BeamNG.drive e usa o AI Dyno Tuner!
    echo.
) else (
    echo.
    echo [INFO] Se o comando 'ollama' ainda nao for reconhecido nesta janela,
    echo fecha o terminal, abre uma nova janela do terminal e corre:
    echo     ollama run llama3.2
    echo.
)

pause
