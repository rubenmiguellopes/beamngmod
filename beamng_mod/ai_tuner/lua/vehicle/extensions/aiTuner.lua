-- ============================================================================
-- BeamNG.drive AI Tuner - Vehicle Lua Bridge Extension
-- Permite recalcular torque, turbo, corte de RPM e embraiagem em tempo real
-- sem recarregar o veículo e de forma 100% segura contra Stack Overflow.
-- ============================================================================

local M = {}

local logTag = "aiTuner"
local constants = {
  rpmToAV = 0.10471975511965977,
  avToRPM = 9.549296585513721
}

-- Armazena os dados originais de fábrica para permitir reset
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

-- Guarda os dados originais do veículo
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
    if dev.type == "frictionClutch" or dev.name == "clutch" or dev.name == "mainClutch" then
      M.originalData.clutchLockTorque[dev.name] = dev.lockTorque
    end
  end

  M.originalData.saved = true
  log("I", logTag, "Especificações originais do motor guardadas em memória.")
end

-- ============================================================================
-- Aplica a afinação mecânica com segurança
-- ============================================================================
local function applyTune(params)
  if not params or type(params) ~= "table" then
    log("E", logTag, "applyTune: parâmetros inválidos.")
    return { success = false, error = "Parâmetros inválidos." }
  end

  local mainEngine = powertrain.getDevice("mainEngine")
  if not mainEngine then
    log("W", logTag, "Nenhum motor de combustão (mainEngine) encontrado.")
    guihooks.message({txt = "AI Tuner: Este veículo não possui um motor de combustão ajustável!", context = {}}, 4, "aiTuner.error")
    return { success = false, error = "Dispositivo mainEngine não encontrado." }
  end

  -- Salvar especificações antes da primeira alteração
  saveOriginalSpecs(mainEngine)

  local torqueMod = tonumber(params.torqueModMult) or 1.0
  local targetMaxRPM = tonumber(params.maxRPM)
  local targetWastegatePSI = tonumber(params.wastegateStartPSI)
  local targetClutchTorque = tonumber(params.clutchTorque) or 1400

  log("I", logTag, string.format("Aplicando afinação: x%.2f Torque | %s RPM | %s PSI | %d Nm Embraiagem",
    torqueMod, tostring(targetMaxRPM), tostring(targetWastegatePSI), targetClutchTorque))

  -- 1. CORTE DE RPM / REDLINE
  if targetMaxRPM and targetMaxRPM >= 3000 and targetMaxRPM <= 15000 then
    local newMaxRPM = math.floor(targetMaxRPM)
    local newMaxAV = newMaxRPM * constants.rpmToAV

    mainEngine.maxRPM = newMaxRPM
    mainEngine.maxAV = newMaxAV
    mainEngine.revLimiterRPM = newMaxRPM
    mainEngine.revLimiterAV = newMaxAV
    mainEngine.maxPhysicalAV = newMaxAV * 1.25
    mainEngine.invMaxAV = 1 / math.max(newMaxAV, 1)

    if mainEngine.tempRevLimiterAV then
      mainEngine.tempRevLimiterAV = newMaxAV * 10
    end
  end

  -- 2. ESCALA DA CURVA DE TORQUE (Sem quebrar a indexação de inteiros do BeamNG)
  if torqueMod and torqueMod > 0 and M.originalData.torqueCurve then
    local origCurve = M.originalData.torqueCurve
    local origMaxRPM = M.originalData.maxRPM or 7000
    local lastKnownTorque = 120

    -- Atualiza pontos originais com multiplicador
    for rpm, tq in pairs(origCurve) do
      if type(rpm) == "number" and type(tq) == "number" then
        mainEngine.torqueCurve[rpm] = tq * torqueMod
        if rpm >= origMaxRPM - 100 then
          lastKnownTorque = tq
        end
      end
    end

    -- Preenche continuamente até o novo corte se a rotação foi aumentada
    local targetLimit = math.floor(mainEngine.maxRPM or origMaxRPM)
    if targetLimit > origMaxRPM then
      for r = origMaxRPM + 1, targetLimit + 200 do
        local taper = math.max(0.65, 1.0 - ((r - origMaxRPM) / (targetLimit - origMaxRPM + 1)) * 0.35)
        mainEngine.torqueCurve[r] = lastKnownTorque * torqueMod * taper
      end
    end

    -- Previne danos por sobretorque / sobregiro
    mainEngine.maxTorqueRating = -1
    mainEngine.maxOverTorqueDamage = 9999999
    mainEngine.maxOverRevDamage = 9999999
    if mainEngine.overTorqueDamage then mainEngine.overTorqueDamage = 0 end
  end

  -- 3. AJUSTE DE TURBO / WASTEGATE
  if targetWastegatePSI and targetWastegatePSI > 0 then
    local jbeamData = mainEngine.jbeamData
    if jbeamData and jbeamData.turbocharger and v.data[jbeamData.turbocharger] then
      local turboJbeam = v.data[jbeamData.turbocharger]
      turboJbeam.wastegateStart = targetWastegatePSI
      turboJbeam.wastegateLimit = targetWastegatePSI + 2.5

      if mainEngine.turbocharger and type(mainEngine.turbocharger.init) == "function" then
        pcall(mainEngine.turbocharger.init, mainEngine, turboJbeam)
      end
    end
  end

  -- 4. REFORÇO DA EMBRAIAGEM
  local devices = powertrain.getDevices() or {}
  for _, dev in pairs(devices) do
    if dev.type == "frictionClutch" or dev.name == "clutch" or dev.name == "mainClutch" then
      dev.lockTorque = math.max(dev.lockTorque or 0, targetClutchTorque)
      if dev.lockSpring then
        dev.lockSpring = math.max(dev.lockSpring, targetClutchTorque * 1.5)
      end
      dev.damageLockTorqueCoef = 1
      dev.clutchPermanentlyDamaged = false
    end
  end

  -- 5. ATUALIZAR DADOS INTERNOS COM SEGURANÇA (Sem manipular tabelas UI diretamente)
  if type(mainEngine.updateTorqueData) == "function" then
    pcall(mainEngine.updateTorqueData, mainEngine)
  end

  local summaryMsg = params.summary or string.format("Afinação Aplicada: x%.1f Torque | %d RPM", torqueMod, mainEngine.maxRPM)
  guihooks.message({txt = summaryMsg, context = {}}, 5, "aiTuner.success")

  return {
    success = true,
    summary = summaryMsg
  }
end

-- ============================================================================
-- Restaura os parâmetros de fábrica
-- ============================================================================
local function resetToStock()
  local mainEngine = powertrain.getDevice("mainEngine")
  if not mainEngine or not M.originalData.saved then
    guihooks.message({txt = "AI Tuner: O veículo já está nas configurações de fábrica.", context = {}}, 4, "aiTuner.info")
    return { success = false, message = "Sem dados originais." }
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
      pcall(mainEngine.turbocharger.init, mainEngine, turboJbeam)
    end
  end

  -- Restaurar embraiagens
  local devices = powertrain.getDevices() or {}
  for _, dev in pairs(devices) do
    if M.originalData.clutchLockTorque[dev.name] then
      dev.lockTorque = M.originalData.clutchLockTorque[dev.name]
    end
  end

  if type(mainEngine.updateTorqueData) == "function" then
    pcall(mainEngine.updateTorqueData, mainEngine)
  end

  guihooks.message({txt = "AI Tuner: Configurações de fábrica restauradas!", context = {}}, 4, "aiTuner.stock")
  return { success = true, summary = "Motor restaurado para fábrica." }
end

-- ============================================================================
-- Decodificação JSON segura
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

  return { success = false, error = "Tipo inválido." }
end

local function onInit()
  log("I", logTag, "AI Tuner carregado no veículo.")
end

M.onInit = onInit
M.applyTune = applyTune
M.applyTuneJson = applyTuneJson
M.resetToStock = resetToStock

return M
