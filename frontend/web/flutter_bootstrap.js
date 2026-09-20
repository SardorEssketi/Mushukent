{{flutter_js}}
{{flutter_build_config}}

(function () {
  "use strict";

  var firstFrameRendered = false;
  var startupRoot = document.getElementById("flutter-startup");
  var startupStatus = document.getElementById("flutter-startup-status");

  function logStage(stage, details) {
    if (details === undefined) {
      console.info("[Mushukistan startup] " + stage);
    } else {
      console.info("[Mushukistan startup] " + stage, details);
    }
  }

  function setStatus(message) {
    if (startupStatus) {
      startupStatus.textContent = message;
    }
  }

  function showFailure(error) {
    if (firstFrameRendered) {
      return;
    }
    console.error("[Mushukistan startup] Flutter startup failed", error);
    setStatus("Mushukistan could not start.");
    if (startupRoot) {
      startupRoot.classList.add("startup-failed");
    }
  }

  function isFlutterServiceWorker(worker) {
    if (!worker || !worker.scriptURL) {
      return false;
    }
    try {
      return new URL(worker.scriptURL, window.location.href).pathname.endsWith(
        "/flutter_service_worker.js"
      );
    } catch (_) {
      return false;
    }
  }

  async function retireLegacyFlutterServiceWorker() {
    if (!("serviceWorker" in navigator)) {
      return false;
    }

    try {
      var registrations = await navigator.serviceWorker.getRegistrations();
      var controlledByFlutter = isFlutterServiceWorker(
        navigator.serviceWorker.controller
      );
      var retired = false;

      for (var i = 0; i < registrations.length; i += 1) {
        var registration = registrations[i];
        var ownsFlutterWorker =
          isFlutterServiceWorker(registration.active) ||
          isFlutterServiceWorker(registration.waiting) ||
          isFlutterServiceWorker(registration.installing);
        if (ownsFlutterWorker) {
          retired = (await registration.unregister()) || retired;
        }
      }

      if (controlledByFlutter && retired) {
        logStage("legacy service worker retired; reloading once");
        window.location.reload();
        return true;
      }
    } catch (error) {
      console.warn(
        "[Mushukistan startup] Legacy service worker cleanup failed; continuing",
        error
      );
    }
    return false;
  }

  window.addEventListener(
    "flutter-first-frame",
    function () {
      firstFrameRendered = true;
      logStage("first Flutter frame");
      if (startupRoot) {
        startupRoot.remove();
        startupRoot = null;
        startupStatus = null;
      }
    },
    { once: true }
  );

  window.addEventListener("error", function (event) {
    if (!firstFrameRendered) {
      showFailure(event.error || event.message);
    }
  });

  window.addEventListener("unhandledrejection", function (event) {
    if (!firstFrameRendered) {
      showFailure(event.reason);
    }
  });

  async function startFlutter() {
    logStage("web bootstrap started");
    setStatus("Preparing Mushukistan…");
    if (await retireLegacyFlutterServiceWorker()) {
      return;
    }

    setStatus("Loading the application…");
    await _flutter.loader.load({
      onEntrypointLoaded: async function (engineInitializer) {
        logStage("Dart entrypoint loaded");
        setStatus("Starting the application…");
        var appRunner = await engineInitializer.initializeEngine();
        logStage("Flutter engine initialized");
        await appRunner.runApp();
        logStage("Flutter application mounted");
      },
    });
  }

  startFlutter().catch(showFailure);
})();
