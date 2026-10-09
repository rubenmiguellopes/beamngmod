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

      // Verificar conectividade com o backend Python
      $scope.checkBackendHealth = function () {
        fetch($scope.backendUrl + '/health', {
          method: 'GET',
          cache: 'no-cache'
        })
        .then(function (res) {
          if (res.ok) return res.json();
          throw new Error('Servidor retornou código ' + res.status);
        })
        .then(function (data) {
          $scope.$evalAsync(function () {
            $scope.backendOnline = true;
            $scope.backendInfo = data.model || 'Online';
          });
        })
        .catch(function () {
          $scope.$evalAsync(function () {
            $scope.backendOnline = false;
          });
        });
      };

      // Executa teste de conectividade inicial
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

      // Enviar prompt para a IA e injetar no veículo
      $scope.tune = function () {
        var query = ($scope.prompt || '').trim();
        if (!query) {
          $scope.status = 'Escreve um pedido antes de clicar em tunar.';
          $scope.statusType = 'error';
          return;
        }

        $scope.isLoading = true;
        $scope.status = 'A consultar IA mecânica e calculando powertrain...';
        $scope.statusType = 'loading';

        fetch($scope.backendUrl + '/tune', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ prompt: query })
        })
        .then(function (response) {
          if (!response.ok) {
            return response.json().then(function (err) {
              throw new Error(err.error || ('Erro HTTP ' + response.status));
            });
          }
          return response.json();
        })
        .then(function (result) {
          if (!result || !result.success || !result.data) {
            throw new Error(result.error || 'A IA não devolveu parâmetros válidos.');
          }

          var tuneData = result.data;
          $scope.backendOnline = true;

          // Injetar código Lua diretamente no veículo ativo em tempo real
          var jsonPayload = JSON.stringify(tuneData).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
          var luaCommand = 'extensions.load("aiTuner"); if extensions.aiTuner then extensions.aiTuner.applyTuneJson(\'' + jsonPayload + '\') end';

          if (window.bngApi && typeof window.bngApi.activeObjectLua === 'function') {
            window.bngApi.activeObjectLua(luaCommand);
          } else if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
            window.bngApi.engineLua('if be:getPlayerVehicle(0) then be:getPlayerVehicle(0):queueLuaCommand("' + luaCommand.replace(/"/g, '\\"') + '") end');
          } else {
            console.warn('[AI Tuner] bngApi não está presente no ambiente de testes CEF.');
          }

          $scope.$evalAsync(function () {
            $scope.isLoading = false;
            $scope.lastTune = tuneData;
            $scope.status = tuneData.summary || 'Afinação aplicada com sucesso!';
            $scope.statusType = 'success';
          });
        })
        .catch(function (error) {
          $scope.$evalAsync(function () {
            $scope.isLoading = false;
            $scope.status = 'Falha: ' + (error.message || 'Servidor Python offline em 127.0.0.1:5000');
            $scope.statusType = 'error';
            $scope.backendOnline = false;
          });
        });
      };

      // Restaurar configurações originais de fábrica
      $scope.restoreStock = function () {
        var luaReset = 'if extensions.aiTuner then extensions.aiTuner.resetToStock() end';
        if (window.bngApi && typeof window.bngApi.activeObjectLua === 'function') {
          window.bngApi.activeObjectLua(luaReset);
        } else if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('if be:getPlayerVehicle(0) then be:getPlayerVehicle(0):queueLuaCommand("' + luaReset.replace(/"/g, '\\"') + '") end');
        }

        $scope.status = 'Motor restaurado para as especificações de fábrica.';
        $scope.statusType = 'idle';
        $scope.lastTune = null;
      };

    }]
  };
}]);
