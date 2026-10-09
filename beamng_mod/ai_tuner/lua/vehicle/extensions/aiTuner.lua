-- ============================================================================
-- BeamNG.drive AI Tuner - Vehicle Lua Bridge Extension
-- Permite recalcular torque, turbo, corte de RPM e embraiagem em tempo real
-- sem necessidade de recarregar o veículo (sem reload).
-- ============================================================================

local M = {}

local logTag = "aiTuner"
local constants = constants or {
  rpmToAV = 0.10471975511965977,
  avToRPM = 9.549296585513721,
  psiToPascal = 6894.757,
  torqueToPower = 0.0001404345
}

-- Armazena os dados originais de fábrica para permitir reset ou ajustes progressivos
M.originalData = {
  saved = false,
  torqueCurve = nil,
  maxRPM = nil,
  maxAV = nil,
  revLimiterRPM = nil,
  revLimiterAV = nil,
  maxPhysicalAV = nil,
  maxTorqueRating = nil,
  wastegateStart = nil,
  wastegateLimit = nil,
  clutchLockTorque = {}
}

-- Salva os dados de fábrica do veículo atual
local function saveOriginalSpecs(mainEngine)
  if M.originalData.saved or not mainEngine or not mainEngine.torqueCurve then
    return
  end

  M.originalData.torqueCurve = shallowcopy(mainEngine.torqueCurve)
  M.originalData.maxRPM = mainEngine.maxRPM
  M.originalData.maxAV = mainEngine.maxAV
  M.originalData.revLimiterRPM = mainEngine.revLimiterRPM
  M.originalData.revLimiterAV = mainEngine.revLimiterAV
  M.originalData.maxPhysicalAV = mainEngine.maxPhysicalAV
  M.originalData.maxTorqueRating = mainEngine.maxTorqueRating

  -- Guardar wastegate original se existir
  if mainEngine.jbeamData and mainEngine.jbeamData.turbocharger and v.data[mainEngine.jbeamData.turbocharger] then
    local turboJbeam = v.data[mainEngine.jbeamData.turbocharger]
    M.originalData.wastegateStart = turboJbeam.wastegateStart
    M.originalData.wastegateLimit = turboJbeam.wastegateLimit
  end

  -- Guardar embraiagens originais
  local devices = powertrain.getDevices() or {}
  for _, dev in pairs(devices) do
    if dev.type == "frictionClutch" or dev.name == "clutch" then
      M.originalData.clutchLockTorque[dev.name] = dev.lockTorque
    end
  end

  M.originalData.saved = true
  log("I", logTag, "Especificações originais do motor salvas em memória com sucesso.")
end

-- ============================================================================
-- Função Principal: Aplica o setup gerado pela IA no veículo ativo
-- ============================================================================
local function applyTune(params)
  if not params or type(params) ~= "table" then
    log("E", logTag, "applyTune recebeu parâmetros inválidos (não é uma tabela).")
    return { success = false, error = "Parâmetros inválidos." }
  end

  local mainEngine = powertrain.getDevice("mainEngine")
  if not mainEngine then
    log("W", logTag, "Nenhum dispositivo 'mainEngine' encontrado neste veículo.")
    guihooks.message({txt = "AI Tuner: Este veículo não possui um motor de combustão ajustável!", context = {}}, 5, "aiTuner.error")
    return { success = false, error = "Dispositivo mainEngine não encontrado." }
  end

  -- Garantir que guardamos as especificações originais na primeira execução
  saveOriginalSpecs(mainEngine)

  -- Extrair parâmetros com saneamento
  local torqueMod = tonumber(params.torqueModMult) or 1.0
  local targetMaxRPM = tonumber(params.maxRPM)
  local targetWastegatePSI = tonumber(params.wastegateStartPSI)
  local targetClutchTorque = tonumber(params.clutchTorque) or 1500

  log("I", logTag, string.format("Aplicando Tune: Mult=%.2f, RPM=%s, Wastegate=%s PSI, Embraiagem=%s Nm",
    torqueMod, tostring(targetMaxRPM), tostring(targetWastegatePSI), tostring(targetClutchTorque)))

  -- --------------------------------------------------------------------------
  -- 1. AUMENTAR REDLINE / CORTE DE RPM
  -- --------------------------------------------------------------------------
  if targetMaxRPM and targetMaxRPM >= 3000 and targetMaxRPM <= 15000 then
    local rpmToAV = constants.rpmToAV or (math.pi / 30)
    local newMaxRPM = math.floor(targetMaxRPM)
    local newMaxAV = newMaxRPM * rpmToAV

    mainEngine.maxRPM = newMaxRPM
    mainEngine.maxAV = newMaxAV
    mainEngine.revLimiterRPM = newMaxRPM
    mainEngine.revLimiterAV = newMaxAV
    mainEngine.maxPhysicalAV = newMaxAV * 1.25
    mainEngine.invMaxAV = 1 / math.max(newMaxAV, 1)

    -- Atualizar limiter temporário caso o veículo utilize controle de tração/launch
    if mainEngine.tempRevLimiterAV then
      mainEngine.tempRevLimiterAV = newMaxAV * 10
    end
    log("I", logTag, "Novo limitador de rotações definido para " .. tostring(newMaxRPM) .. " RPM.")
  end

  -- --------------------------------------------------------------------------
  -- 2. AJUSTAR CURVA DE TORQUE DO MOTOR (torqueCurve)
  -- --------------------------------------------------------------------------
  if torqueMod and torqueMod > 0 then
    local baseCurve = M.originalData.torqueCurve or mainEngine.torqueCurve
    local newTorqueCurve = {}
    local highestRpmInBase = 0
    local lastKnownTorque = 120

    -- Multiplicar todos os pontos da curva original
    for rpm, tq in pairs(baseCurve) do
      if type(rpm) == "number" then
        newTorqueCurve[rpm] = tq * torqueMod
        if rpm > highestRpmInBase then
          highestRpmInBase = rpm
          lastKnownTorque = newTorqueCurve[rpm]
        end
      end
    end

    -- Se o novo maxRPM for superior ao fim da curva original, extrapolar suavemente
    local currentMaxRPM = mainEngine.maxRPM or highestRpmInBase
    if currentMaxRPM > highestRpmInBase then
      local step = 200
      for r = highestRpmInBase + step, currentMaxRPM + 400, step do
        -- Decaimento suave de alta rotação (taper off) para física realista
        local falloff = math.max(0.75, 1.0 - ((r - highestRpmInBase) / currentMaxRPM) * 0.35)
        newTorqueCurve[r] = lastKnownTorque * falloff
      end
    end

    mainEngine.torqueCurve = newTorqueCurve

    -- Proteger o bloco do motor contra quebra imediata por sobrebinário/sobregiro
    mainEngine.maxTorqueRating = -1 -- Desativa dano por overtorque no BeamNG
    mainEngine.maxOverTorqueDamage = 9999999
    mainEngine.maxOverRevDamage = 9999999
    if mainEngine.overTorqueDamage then
      mainEngine.overTorqueDamage = 0
    end
    if damageTracker and damageTracker.setDamage then
      damageTracker.setDamage("engine", "overTorqueDanger", false)
      damageTracker.setDamage("engine", "catastrophicOverTorqueDamage", false)
      damageTracker.setDamage("engine", "overRevDanger", false)
    end
    log("I", logTag, "Curva de binário escalada com sucesso. Multiplicador: " .. tostring(torqueMod))
  end

  -- --------------------------------------------------------------------------
  -- 3. AJUSTAR TURBOCHARGER / WASTEGATE (Pressão de Boost)
  -- --------------------------------------------------------------------------
  local turboAdjusted = false
  if targetWastegatePSI and targetWastegatePSI > 0 then
    local jbeamData = mainEngine.jbeamData
    if jbeamData and jbeamData.turbocharger and v.data[jbeamData.turbocharger] then
      local turboJbeam = v.data[jbeamData.turbocharger]
      turboJbeam.wastegateStart = targetWastegatePSI
      turboJbeam.wastegateLimit = targetWastegatePSI + 2.5

      -- Reinicializar subsistema do turbo em tempo real
      if mainEngine.turbocharger and type(mainEngine.turbocharger.init) == "function" then
        mainEngine.turbocharger.init(mainEngine, turboJbeam)
        turboAdjusted = true
        log("I", logTag, "Turbocharger reconfigurado para wastegate a " .. tostring(targetWastegatePSI) .. " PSI.")
      end
    end

    -- Se o carro não tiver turbo nativo na JBeam, o multiplicador de torque já dá a potência!
    if not turboAdjusted then
      log("I", logTag, "Veículo aspirado: potência gerada via curva direta de torque.")
    end
  end

  -- --------------------------------------------------------------------------
  -- 4. REFORÇAR A EMBRAIAGEM (Prevenir embraiagem patinando com alta potência)
  -- --------------------------------------------------------------------------
  local devices = powertrain.getDevices() or {}
  for _, dev in pairs(devices) do
    if dev.type == "frictionClutch" or dev.name == "clutch" or dev.name == "mainClutch" then
      dev.lockTorque = math.max(dev.lockTorque or 0, targetClutchTorque)
      if dev.lockSpring then
        dev.lockSpring = math.max(dev.lockSpring, targetClutchTorque * 1.6)
      end
      if dev.maxClutchAngle and dev.lockSpring then
        dev.maxClutchAngle = math.sqrt(dev.lockTorque / dev.lockSpring) + math.max(dev.lockTorque / dev.lockSpring - 1, 0)
      end
      dev.damageLockTorqueCoef = 1
      dev.clutchPermanentlyDamaged = false
      log("I", logTag, "Embraiagem '" .. tostring(dev.name) .. "' reforçada para " .. tostring(targetClutchTorque) .. " Nm.")
    end
  end

  -- --------------------------------------------------------------------------
  -- 5. ATUALIZAR TABELAS DE DADOS E NOTIFICAR A UI DO BEAMNG
  -- --------------------------------------------------------------------------
  local peakTorque = 0
  for _, tq in pairs(mainEngine.torqueCurve) do
    if type(tq) == "number" and tq > peakTorque then
      peakTorque = tq
    end
  end

  if type(mainEngine.torqueData) == "table" then
    mainEngine.torqueData.maxTorque = peakTorque
    mainEngine.torqueData.maxRPM = mainEngine.maxRPM
    if mainEngine.torqueData.curves and mainEngine.torqueData.curves[1] then
      mainEngine.torqueData.curves[1].torque = mainEngine.torqueCurve
    end
  end

  -- Feedback visual e notificação dentro do BeamNG
  local summaryMsg = params.summary or string.format("AI Tune: x%.1f Torque | %d RPM | %d PSI", torqueMod, mainEngine.maxRPM, targetWastegatePSI or 0)
  guihooks.message({txt = summaryMsg, context = {}}, 6, "aiTuner.success")

  return {
    success = true,
    summary = summaryMsg,
    appliedSpecs = {
      torqueModMult = torqueMod,
      maxRPM = mainEngine.maxRPM,
      wastegateStartPSI = targetWastegatePSI or 0,
      clutchTorque = targetClutchTorque,
      peakTorqueNm = math.floor(peakTorque)
    }
  }
end

-- ============================================================================
-- Desfazer modificações e restaurar os dados de fábrica do carro
-- ============================================================================
local function resetToStock()
  local mainEngine = powertrain.getDevice("mainEngine")
  if not mainEngine or not M.originalData.saved then
    guihooks.message({txt = "AI Tuner: Carro já está com as configurações de fábrica.", context = {}}, 4, "aiTuner.info")
    return { success = false, message = "Sem dados originais salvos." }
  end

  mainEngine.torqueCurve = shallowcopy(M.originalData.torqueCurve)
  mainEngine.maxRPM = M.originalData.maxRPM
  mainEngine.maxAV = M.originalData.maxAV
  mainEngine.revLimiterRPM = M.originalData.revLimiterRPM
  mainEngine.revLimiterAV = M.originalData.revLimiterAV
  mainEngine.maxPhysicalAV = M.originalData.maxPhysicalAV
  mainEngine.maxTorqueRating = M.originalData.maxTorqueRating

  -- Restaurar turbo
  if mainEngine.jbeamData and mainEngine.jbeamData.turbocharger and v.data[mainEngine.jbeamData.turbocharger] and M.originalData.wastegateStart then
    local turboJbeam = v.data[mainEngine.jbeamData.turbocharger]
    turboJbeam.wastegateStart = M.originalData.wastegateStart
    turboJbeam.wastegateLimit = M.originalData.wastegateLimit
    if mainEngine.turbocharger and type(mainEngine.turbocharger.init) == "function" then
      mainEngine.turbocharger.init(mainEngine, turboJbeam)
    end
  end

  -- Restaurar embraiagens
  local devices = powertrain.getDevices() or {}
  for _, dev in pairs(devices) do
    if M.originalData.clutchLockTorque[dev.name] then
      dev.lockTorque = M.originalData.clutchLockTorque[dev.name]
    end
  end

  guihooks.message({txt = "AI Tuner: Configurações originais de fábrica restauradas!", context = {}}, 5, "aiTuner.stock")
  log("I", logTag, "Configurações originais restauradas.")
  return { success = true, summary = "Motor restaurado para as especificações de fábrica." }
end

-- ============================================================================
-- Wrappers para chamadas via JS / bngApi
-- ============================================================================
local function applyTuneJson(jsonStringOrTable)
  if type(jsonStringOrTable) == "table" then
    return applyTune(jsonStringOrTable)
  end

  if type(jsonStringOrTable) == "string" then
    local ok, parsed = pcall(jsonDecode, jsonStringOrTable)
    if ok and parsed then
      return applyTune(parsed)
    else
      log("E", logTag, "Falha ao decodificar JSON: " .. tostring(jsonStringOrTable))
      return { success = false, error = "JSON decode error" }
    end
  end

  return { success = false, error = "Tipo de argumento desconhecido." }
end

-- Lifecycle hooks do BeamNG
local function onInit()
  log("I", logTag, "Extensão AI Tuner inicializada.")
end

local function onReset()
  -- Ao resetar o veículo (tecla 'R' ou 'I'), os valores em memória persistem
end

M.onInit = onInit
M.onReset = onReset
M.applyTune = applyTune
M.applyTuneJson = applyTuneJson
M.resetToStock = resetToStock

return M
