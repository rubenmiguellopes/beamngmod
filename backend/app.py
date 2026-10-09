"""
BeamNG.drive AI Tuner - Backend Server
Configurado para IA Local 100% Gratuita (Ollama) ou Provedores Cloud (OpenAI/Claude)
"""

import os
import re
import json
import logging
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import openai
from openai import OpenAI

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s in %(module)s: %(message)s'
)
logger = logging.getLogger("AITunerBackend")

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# Configuração Padrão: Ollama Local (Gratuito e sem limites)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "ollama")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "http://localhost:11434/v1")
MODEL_NAME = os.getenv("MODEL_NAME", "llama3.2")

client_kwargs = {
    "api_key": OPENAI_API_KEY if OPENAI_API_KEY else "ollama",
    "base_url": OPENAI_BASE_URL if OPENAI_BASE_URL else "http://localhost:11434/v1",
    "max_retries": 0,
    "timeout": 8.0
}

client = OpenAI(**client_kwargs)

SYSTEM_PROMPT = """Você é um preparador de motores e engenheiro mecânico especializado no BeamNG.drive.
O utilizador vai enviar um pedido em linguagem natural para alterar a potência ou comportamento do carro (ex: "carro com 1100hp e turbo a 35 psi", "setup drift 700hp", "modo eco").

Interprete o pedido e calcule os parâmetros exatos para o motor e powertrain do BeamNG.

Responda APENAS com um objeto JSON válido, sem texto adicional, sem formatação markdown (não use ```json):
{
  "torqueModMult": <float de 0.3 a 8.0, onde 1.0 é stock, 2.0 duplica o binário>,
  "wastegateStartPSI": <float de 0 a 65, pressão do turbo em PSI. Use 0 se for aspirado>,
  "maxRPM": <int de 4500 a 12000, rotação máxima / redline do motor>,
  "clutchTorque": <int de 400 a 4000, capacidade da embraiagem em Nm>,
  "summary": "<frase curta em português resumindo a preparação>"
}

Regras:
- 1100hp -> torqueModMult ~ 2.2 a 2.5, wastegate ~ 30 a 38 PSI, clutchTorque ~ 1400 Nm.
- 700hp drift -> torqueModMult ~ 1.6 a 1.9, wastegate ~ 18 a 24 PSI, clutchTorque ~ 1100 Nm.
- Drag monstro 1500hp+ -> torqueModMult ~ 3.5 a 5.0, wastegate ~ 45 a 60 PSI, clutchTorque ~ 2500 Nm.
- Modo económico / aspirado -> torqueModMult ~ 0.6 a 0.9, wastegate 0 PSI, maxRPM ~ 5500 RPM.
"""

def extract_json(raw_text: str) -> dict:
    """Extrai e valida JSON com segurança."""
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```[a-zA-Z]*\n?", "", cleaned)
        cleaned = re.sub(r"\n?```$", "", cleaned)
        cleaned = cleaned.strip()
        
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, re.DOTALL)
        if match:
            return json.loads(match.group(0))
        raise ValueError(f"Não foi possível converter a resposta em JSON: {raw_text}")

def sanitize_tune_data(data: dict) -> dict:
    """Garante parâmetros em intervalos seguros para a física do BeamNG."""
    torque = float(data.get("torqueModMult", 1.0))
    torque = max(0.2, min(10.0, torque))
    
    wastegate = float(data.get("wastegateStartPSI", 0.0))
    wastegate = max(0.0, min(80.0, wastegate))
    
    rpm = int(data.get("maxRPM", 7500))
    rpm = max(3000, min(14000, rpm))
    
    clutch = int(data.get("clutchTorque", 1200))
    clutch = max(300, min(5000, clutch))
    
    summary = str(data.get("summary", "Afinação aplicada."))
    
    return {
        "torqueModMult": round(torque, 2),
        "wastegateStartPSI": round(wastegate, 1),
        "maxRPM": rpm,
        "clutchTorque": clutch,
        "summary": summary
    }

@app.route("/health", methods=["GET"])
def health_check():
    is_local = "localhost" in client_kwargs.get("base_url", "") or "127.0.0.1" in client_kwargs.get("base_url", "")
    return jsonify({
        "status": "online",
        "service": "BeamNG AI Tuner Backend",
        "provider": "Ollama Local (Gratuito)" if is_local else "Cloud API",
        "model": MODEL_NAME,
        "endpoint": client_kwargs.get("base_url")
    }), 200

def heuristic_fallback_tune(prompt: str) -> dict:
    prompt_lower = prompt.lower()
    torque_mult = 1.5
    wastegate = 15.0
    rpm = 7500
    clutch = 1200
    summary_parts = []
    
    # Deteta HP / Cavalos
    hp_match = re.search(r'(\d{2,4})\s*(?:hp|cv|bhp|cavalos)', prompt_lower)
    if hp_match:
        target_hp = int(hp_match.group(1))
        torque_mult = max(0.4, min(7.0, target_hp / 300.0))
        clutch = max(600, min(3800, int(target_hp * 1.5)))
        summary_parts.append(f"{target_hp}hp")
        if target_hp > 500 and "bar" not in prompt_lower and "psi" not in prompt_lower:
            wastegate = min(60.0, (target_hp - 300) / 20.0 + 10.0)

    # Deteta PSI / Turbo
    psi_match = re.search(r'(\d{1,2}(?:\.\d+)?)\s*(?:psi|bar|libras)', prompt_lower)
    if psi_match:
        val = float(psi_match.group(1))
        if "bar" in prompt_lower and val < 6:
            val = val * 14.5
        wastegate = max(0.0, min(75.0, val))
        summary_parts.append(f"{wastegate:.1f} PSI")
    elif "aspirado" in prompt_lower or "na" in prompt_lower or "sem turbo" in prompt_lower:
        wastegate = 0.0
        summary_parts.append("aspirado")

    # Deteta RPM
    rpm_match = re.search(r'(\d{4,5})\s*(?:rpm|corte)', prompt_lower)
    if rpm_match:
        rpm = max(4500, min(12000, int(rpm_match.group(1))))
        summary_parts.append(f"corte a {rpm} RPM")
    elif "drift" in prompt_lower:
        rpm = 8200
    elif "gt3" in prompt_lower or "race" in prompt_lower:
        rpm = 8500

    # Perfis temáticos
    if "drift" in prompt_lower:
        if not hp_match:
            torque_mult = 1.85
            wastegate = 22.0
            clutch = 1300
        summary_parts.insert(0, "Setup Drift")
    elif "drag" in prompt_lower:
        if not hp_match:
            torque_mult = 3.2
            wastegate = 40.0
            clutch = 2400
        summary_parts.insert(0, "Setup Drag")
    elif "eco" in prompt_lower or "econom" in prompt_lower:
        torque_mult = 0.75
        wastegate = 0.0
        rpm = 5200
        clutch = 750
        summary_parts = ["Modo Eco"]

    summary_desc = ", ".join(summary_parts) if summary_parts else "Afinação dinâmica"
    return sanitize_tune_data({
        "torqueModMult": torque_mult,
        "wastegateStartPSI": wastegate,
        "maxRPM": rpm,
        "clutchTorque": clutch,
        "summary": f"{summary_desc} (Powertrain ajustado)"
    })

@app.route("/tune", methods=["POST"])
def tune_vehicle():
    try:
        req_data = request.get_json(force=True, silent=True)
        if not req_data or "prompt" not in req_data:
            return jsonify({
                "success": False,
                "error": "O campo 'prompt' é obrigatório."
            }), 400

        user_prompt = str(req_data["prompt"]).strip()
        if not user_prompt:
            return jsonify({
                "success": False,
                "error": "O prompt não pode estar vazio."
            }), 400

        logger.info(f"Processando prompt: '{user_prompt}'")

        try:
            # Tentar processar com modelo IA (Ollama ou Cloud)
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0.2,
                max_tokens=300
            )

            raw_content = response.choices[0].message.content or "{}"
            logger.info(f"Resposta bruta da IA: {raw_content}")

            parsed_json = extract_json(raw_content)
            sanitized_data = sanitize_tune_data(parsed_json)

            return jsonify({
                "success": True,
                "data": sanitized_data,
                "engine": "llm"
            }), 200

        except Exception as ai_err:
            logger.warning(f"IA indisponível ({ai_err}). Ativando motor de afinação heurístico local.")
            fallback_data = heuristic_fallback_tune(user_prompt)
            return jsonify({
                "success": True,
                "data": fallback_data,
                "engine": "heuristic"
            }), 200

    except Exception as exc:
        err_msg = str(exc)
        logger.error(f"Erro fatal ao processar tune: {err_msg}", exc_info=True)
        return jsonify({
            "success": False,
            "error": err_msg
        }), 500

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    logger.info(f"Servidor iniciado em http://127.0.0.1:{port}")
    logger.info(f"Conectado ao endpoint local: {client_kwargs.get('base_url')} (Modelo: {MODEL_NAME})")
    app.run(host="0.0.0.0", port=port, debug=False)
