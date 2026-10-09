# ⚡ BeamNG.drive - AI Real-Time Powertrain Tuner Mod

Mod para o **BeamNG.drive** que permite afinar motores, turbos, corte de rotações e embraiagem em **tempo real** com prompts de Inteligência Artificial em linguagem natural.

> **100% GRATUITO E LOCAL**: Podes correr a IA diretamente no teu PC (usando a tua placa gráfica) com o **Ollama**, sem pagar nada, sem chaves de API, sem limites e sem enviar dados para a internet!

---

## 📁 Estrutura Completa de Pastas

```text
beamngmod/
│
├── backend/                               # Servidor local Python (API de IA)
│   ├── app.py                             # Servidor Flask com CORS, OpenAI & Prompt Engine
│   ├── requirements.txt                   # Dependências Python (flask, openai, etc.)
│   ├── .env.example                       # Modelo de configuração para chaves e modelos
│   ├── .env                               # Configuração ativa
│   └── run_backend.bat                    # Script para iniciar o servidor com 1 clique
│
├── beamng_mod/                            # Ficheiros do Mod do BeamNG.drive
│   └── ai_tuner/                          # Pasta do Mod Descompactado
│       ├── mod_info.json                  # Informações para o Mod Manager do BeamNG
│       ├── lua/
│       │   └── vehicle/
│       │       └── extensions/
│       │           ├── aiTuner.lua        # Bridge Lua para modificação de Powertrain
│       │           └── auto/
│       │               └── aiTuner.lua    # Auto-carregador para todos os carros gerados
│       └── ui/
│           └── modules/
│               └── apps/
│                   └── AITuner/
│                       ├── app.json       # Metadados e definições do widget de UI
│                       ├── app.js         # Controlador AngularJS + chamadas bngApi
│                       ├── app.html       # Interface gráfica dark/cyberpunk do widget
│                       └── app.png        # Ícone do aplicativo
│
├── install_mod.bat                        # Instalador automático com 1 clique
└── README.md                              # Documentação e manual completo
```

---

## 🚀 Instalação Rápida (1 Clique)

1. Executa o ficheiro **`install_mod.bat`**.
   - O instalador deteta automaticamente a tua diretoria de utilizador do BeamNG (`%LOCALAPPDATA%\BeamNG.drive\0.3x` ou diretoria configurada no `BeamNG.drive.ini`) e copia os ficheiros para a pasta `mods/unpacked/ai_tuner`.

---

## 🛠️ Instalação Manual

Se preferires instalar manualmente:
1. Copia toda a pasta `beamng_mod/ai_tuner/` para a tua pasta de mods descompactados do BeamNG:
   - Caminho padrão:  
     `%LOCALAPPDATA%\BeamNG.drive\<versão-atual>\mods\unpacked\ai_tuner`  
     *(Exemplo: `C:\Users\Ruben\AppData\Local\BeamNG.drive\0.34\mods\unpacked\ai_tuner` ou `D:\current\mods\unpacked\ai_tuner`)*
2. A estrutura final na pasta de mods deve ficar:
   ```text
   mods/unpacked/ai_tuner/
     ├── mod_info.json
     ├── lua/...
     └── ui/...
   ```

---

## 🧠 Configuração do Servidor Backend (IA)

O servidor Flask corre localmente na porta `5000` e atua como ponte entre o jogo e a IA.

### 1. Escolher o Provedor de IA no ficheiro `backend/.env`:

#### Opção A: OpenAI Oficial (GPT-4o ou GPT-4o-mini)
```env
OPENAI_API_KEY=sk-proj-TUA_CHAVE_AQUI
MODEL_NAME=gpt-4o-mini
PORT=5000
```

#### Opção B: Ollama Local (100% Gratuito, Offline e Local)
Instala o [Ollama](https://ollama.com/), descarrega um modelo (`ollama run llama3`) e configura:
```env
OPENAI_API_KEY=ollama
OPENAI_BASE_URL=http://localhost:11434/v1
MODEL_NAME=llama3
PORT=5000
```

#### Opção C: OpenRouter / DeepSeek / Groq
```env
OPENAI_API_KEY=sk-or-v1-TUA_CHAVE_AQUI
OPENAI_BASE_URL=https://openrouter.ai/api/v1
MODEL_NAME=deepseek/deepseek-chat
PORT=5000
```

### 2. Iniciar o Servidor
Basta dar duplo clique em:
`backend/run_backend.bat`

O script instala automaticamente as dependências (`pip install -r requirements.txt`) e inicia o serviço em `http://127.0.0.1:5000`.

---

## 🎮 Como Usar no BeamNG.drive

1. Abre o **BeamNG.drive** e entra em qualquer mapa com qualquer veículo (ex: *Gavril Barstow*, *Cherrier FCV*, *Ibishu 200BX*, *Civetta Scintilla*).
2. Pressiona **ESC** para abrir o menu do jogo.
3. No menu lateral direito, clica em **UI Apps** (ou ícone de widgets).
4. Clica no botão **Add App (+)**.
5. Procura por **"AI Dyno Tuner"** e seleciona-o.
6. Posiciona o widget onde preferires no ecrã e clica na marca de verificação verde (Guardar).
7. Escreve o teu prompt na caixa de texto:
   - *"quero o carro com 1100hp e turbo a 35 psi"*
   - *"afina para drift com 700hp bem responsivo"*
   - *"preparação de arrancada extrema com 1500hp e corte a 9000 rpm"*
   - *"carro civil com 220hp suave para condução urbana"*
8. Clica em **⚡ Tunar com IA** (ou pressiona Enter).
9. O veículo atualiza instantaneamente a potência, pressão de boost, corte de ignição e reforço de embraiagem **sem necessidade de reiniciar o cenário nem recarregar o carro (sem reload)**!

---

## ⚙️ Detalhes da Bridge Lua (Powertrain)

A extensão `lua/vehicle/extensions/aiTuner.lua`:
- **Curva de Binário (`mainEngine.torqueCurve`)**: Multiplica dinamicamente todos os pontos da curva de torque original pelo fator calculado pela IA e extrapola linearmente caso o novo corte de RPM ultrapasse a tabela de fábrica.
- **Limitador de Rotações (`mainEngine.maxRPM`, `revLimiterAV`)**: Ajusta os limites físicos e de corte suave do motor de combustão.
- **Turbocompressor (`mainEngine.turbocharger`)**: Localiza as definições de wastegate e reinicializa o subsistema com nova pressão em Pascal (`targetPSI * 6894.757`), mantendo a física de spool e sons funcionais.
- **Proteção Térmica e de Durabilidade**: Define `maxTorqueRating = -1`, `maxOverTorqueDamage = 9999999` e limpa falhas para evitar que o bloco do motor parta instantaneamente com 1000hp+.
- **Embraiagem (`frictionClutch`)**: Eleva o `lockTorque` e a mola de engate da embraiagem proporcionalmente para evitar que o disco patine sob o binário massivo.
- **Botão Stock**: Guarda os valores de fábrica da viatura na primeira execução e permite regressar às especificações originais a qualquer momento com o botão **↺ Stock**.
