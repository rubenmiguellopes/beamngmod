angular.module('beamng.apps')
.directive('aiTuner', [function () {
  return {
    templateUrl: '/ui/modules/apps/AITuner/app.html',
    replace: true,
    restrict: 'EA',
    scope: true,
    controller: ['$scope', '$timeout', function ($scope, $timeout) {
      'use strict';

      $scope.prompt = '';
      $scope.backendUrl = 'http://127.0.0.1:5000';
      $scope.isLoading = false;
      $scope.backendOnline = false;
      $scope.status = 'Pronto. Escreve uma instrução ou escolhe um preset.';
      $scope.statusType = 'idle'; // idle, loading, success, error
      $scope.lastTune = null;

      // Presets rápidos para teste imediato
      $scope.presets = [
        { label: '🚀 1100hp Drag (35 PSI)', text: 'quero o carro com 1100hp e turbo a 35 psi' },
        { label: '💨 Drift Spec 750hp', text: 'prepara o carro para drift com 750hp e resposta rápida' },
        { label: '🏁 GT3 Race 8500 RPM', text: 'afinação de pista com 650hp aspirado e corte a 8500 rpm' },
        { label: '🌱 Eco Mode', text: 'modo eco com 150hp suave e corte a 5000 rpm' }
      ];

      // Envio de comandos Lua para o veículo ativo
      function sendLuaToVehicle(luaCommand) {
        var api = window.bngApi || (typeof bngApi !== 'undefined' ? bngApi : null);
        if (api && typeof api.activeObjectLua === 'function') {
          api.activeObjectLua(luaCommand);
          return true;
        }
        if (api && typeof api.engineLua === 'function') {
          var escaped = luaCommand.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
          api.engineLua('if be:getPlayerVehicle(0) then be:getPlayerVehicle(0):queueLuaCommand("' + escaped + '") end');
          return true;
        }
        console.warn('[AI Tuner] bngApi não disponível no ambiente atual.');
        return false;
      }

      // Aplica dados de afinação no motor do BeamNG
      function applyTuneData(tuneData) {
        var jsonPayload = JSON.stringify(tuneData).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
        var luaCommand = 'extensions.load("aiTuner"); if extensions.aiTuner then extensions.aiTuner.applyTuneJson(\'' + jsonPayload + '\') end';
        sendLuaToVehicle(luaCommand);
      }

      // Motor de cálculo mecânico local (fallback instantâneo)
      function calculateLocalTune(rawPrompt) {
        var p = (rawPrompt || '').toLowerCase();
        var torqueMult = 1.5;
        var wastegate = 15.0;
        var rpm = 7500;
        var clutch = 1200;
        var parts = [];

        // Deteta Potência (HP / CV)
        var hpMatch = p.match(/(\d{2,4})\s*(?:hp|cv|bhp|cavalos)/);
        if (hpMatch) {
          var hp = parseInt(hpMatch[1], 10);
          torqueMult = Math.max(0.4, Math.min(7.0, hp / 300.0));
          clutch = Math.max(600, Math.min(3800, Math.round(hp * 1.5)));
          parts.push(hp + 'hp');
          if (hp > 500 && !p.includes('bar') && !p.includes('psi') && !p.includes('aspirado')) {
            wastegate = Math.min(60.0, (hp - 300) / 20.0 + 10.0);
          }
        }

        // Deteta Turbo / PSI
        var psiMatch = p.match(/(\d{1,2}(?:\.\d+)?)\s*(?:psi|bar|libras)/);
        if (psiMatch) {
          var val = parseFloat(psiMatch[1]);
          if (p.includes('bar') && val < 6) val = val * 14.5;
          wastegate = Math.max(0.0, Math.min(75.0, val));
          parts.push(wastegate.toFixed(1) + ' PSI');
        } else if (p.includes('aspirado') || p.includes('sem turbo') || p.includes(' na ')) {
          wastegate = 0.0;
          parts.push('aspirado');
        }

        // Deteta Corte de RPM
        var rpmMatch = p.match(/(\d{4,5})\s*(?:rpm|corte)/);
        if (rpmMatch) {
          rpm = Math.max(4500, Math.min(12000, parseInt(rpmMatch[1], 10)));
          parts.push('corte a ' + rpm + ' RPM');
        } else if (p.includes('drift')) {
          rpm = 8200;
        } else if (p.includes('gt3') || p.includes('race') || p.includes('pista')) {
          rpm = 8500;
        }

        // Perfis temáticos
        if (p.includes('drift')) {
          if (!hpMatch) { torqueMult = 1.85; wastegate = 22.0; clutch = 1300; }
          parts.unshift('Setup Drift');
        } else if (p.includes('drag')) {
          if (!hpMatch) { torqueMult = 3.2; wastegate = 40.0; clutch = 2400; }
          parts.unshift('Setup Drag');
        } else if (p.includes('eco') || p.includes('econom')) {
          torqueMult = 0.75; wastegate = 0.0; rpm = 5200; clutch = 750;
          parts = ['Modo Eco'];
        } else if (p.includes('pista') || p.includes('gt3')) {
          parts.unshift('Setup Pista GT3');
        }

        var summaryText = parts.length > 0 ? parts.join(', ') : 'Afinação aplicada';
        return {
          torqueModMult: parseFloat(torqueMult.toFixed(2)),
          wastegateStartPSI: parseFloat(wastegate.toFixed(1)),
          maxRPM: rpm,
          clutchTorque: clutch,
          summary: summaryText + ' (Motor afinado)'
        };
      }

      // Teste de conectividade com o backend Python
      $scope.checkBackendHealth = function () {
        fetch($scope.backendUrl + '/health', {
          method: 'GET',
          mode: 'cors',
          cache: 'no-cache'
        })
        .then(function (res) {
          if (res.ok) return res.json();
          throw new Error('Código ' + res.status);
        })
        .then(function (data) {
          $scope.$evalAsync(function () {
            $scope.backendOnline = true;
            $scope.backendInfo = data.model || 'Online';
          });
        })
        .catch(function () {
          // Tentar alternativa localhost caso 127.0.0.1 tenha restrições
          fetch('http://localhost:5000/health', { method: 'GET', mode: 'cors' })
          .then(function (res) { if (res.ok) return res.json(); throw new Error(); })
          .then(function (data) {
            $scope.$evalAsync(function () {
              $scope.backendUrl = 'http://localhost:5000';
              $scope.backendOnline = true;
            });
          })
          .catch(function () {
            $scope.$evalAsync(function () {
              $scope.backendOnline = false;
            });
          });
        });
      };

      // Verificar status inicial
      $scope.checkBackendHealth();

      // Aplicar prompt predefinido
      $scope.usePreset = function (presetText) {
        $scope.prompt = presetText;
        $scope.tune();
      };

      // Limpar campo
      $scope.clearPrompt = function () {
        $scope.prompt = '';
      };

      // Enviar prompt para o veículo (com IA ou motor de cálculo direto)
      $scope.tune = function () {
        var query = ($scope.prompt || '').trim();
        if (!query) {
          $scope.status = 'Escreve um pedido antes de clicar em tunar.';
          $scope.statusType = 'error';
          return;
        }

        $scope.isLoading = true;
        $scope.status = 'A preparar powertrain e calculando motor...';
        $scope.statusType = 'loading';

        // Tentar via backend Python / IA
        var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
        var timeoutId = controller ? setTimeout(function () { controller.abort(); }, 4000) : null;

        fetch($scope.backendUrl + '/tune', {
          method: 'POST',
          mode: 'cors',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ prompt: query }),
          signal: controller ? controller.signal : undefined
        })
        .then(function (res) {
          if (timeoutId) clearTimeout(timeoutId);
          if (res.ok) return res.json();
          throw new Error('Servidor indisponível');
        })
        .then(function (result) {
          if (!result || !result.success || !result.data) {
            throw new Error('Resposta de dados inválida');
          }
          var tuneData = result.data;
          applyTuneData(tuneData);

          $scope.$evalAsync(function () {
            $scope.isLoading = false;
            $scope.backendOnline = true;
            $scope.lastTune = tuneData;
            $scope.status = tuneData.summary || 'Afinação aplicada com sucesso!';
            $scope.statusType = 'success';
          });
        })
        .catch(function () {
          if (timeoutId) clearTimeout(timeoutId);
          // Fallback Automático e Transparente: Calcula e injeta diretamente no BeamNG!
          var fallbackTune = calculateLocalTune(query);
          applyTuneData(fallbackTune);

          $scope.$evalAsync(function () {
            $scope.isLoading = false;
            $scope.lastTune = fallbackTune;
            $scope.status = fallbackTune.summary || 'Afinação aplicada com sucesso!';
            $scope.statusType = 'success';
          });
        });
      };

      // Restaurar configurações originais de fábrica
      $scope.restoreStock = function () {
        var luaReset = 'if extensions.aiTuner then extensions.aiTuner.resetToStock() end';
        sendLuaToVehicle(luaReset);

        $scope.status = 'Motor restaurado para as especificações de fábrica.';
        $scope.statusType = 'idle';
        $scope.lastTune = null;
      };

    }]
  };
}]);
