(function () {
  "use strict";
  var root = document.documentElement;
  var toggle = document.querySelector(".theme-toggle");
  var menu = document.querySelector(".menu-toggle");
  var mobile = document.getElementById("mobile-nav");
  try {
    var saved = localStorage.getItem("mushukistan-site-theme");
    if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  } catch (_) {}
  function isDark() {
    return root.dataset.theme === "dark" || (root.dataset.theme !== "light" && matchMedia("(prefers-color-scheme: dark)").matches);
  }
  // Cookieless page-view beacon: no cookies, no storage, no person profile. It uses PostHog's
  // cookieless server hash mode (same payload as posthog-js cookieless_mode "always"): PostHog
  // derives a visitor and session id from a daily-rotating salted hash on its servers, so daily
  // unique visitors and sessions are counted without a persistent identifier. Requires "Cookieless
  // server hash mode" in the PostHog project settings. The token is a public write-only key.
  try {
    var host = location.hostname;
    if (host !== "localhost" && host !== "127.0.0.1" && navigator.doNotTrack !== "1") {
      var timezone;
      try { timezone = Intl.DateTimeFormat().resolvedOptions().timeZone; } catch (_) {}
      fetch("https://eu.i.posthog.com/i/v0/e/", {
        method: "POST",
        keepalive: true,
        headers: { "Content-Type": "text/plain" },
        body: JSON.stringify({
          api_key: "phc_mmQo5L8B4scoCC4dg4ofuxuncefhwoAdMpcHrFSU3PCm",
          event: "$pageview",
          distinct_id: "$posthog_cookieless",
          properties: {
            $cookieless_mode: true,
            $process_person_profile: false,
            $lib: "mushukistan-site",
            $raw_user_agent: navigator.userAgent,
            $timezone: timezone,
            $current_url: location.href,
            $host: host,
            $pathname: location.pathname,
            $referrer: document.referrer || "$direct",
            $referring_domain: document.referrer ? new URL(document.referrer).hostname : "$direct",
            $screen_width: screen.width,
            $screen_height: screen.height,
            $language: navigator.language,
            site_lang: root.lang
          }
        })
      }).catch(function () {});
    }
  } catch (_) {}
  if (toggle) {
    toggle.setAttribute("aria-pressed", String(isDark()));
    toggle.addEventListener("click", function () {
      root.dataset.theme = isDark() ? "light" : "dark";
      toggle.setAttribute("aria-pressed", String(isDark()));
      try { localStorage.setItem("mushukistan-site-theme", root.dataset.theme); } catch (_) {}
    });
  }
  if (menu && mobile) {
    menu.addEventListener("click", function () {
      var expanded = menu.getAttribute("aria-expanded") === "true";
      menu.setAttribute("aria-expanded", String(!expanded));
      menu.setAttribute("aria-label", expanded ? menu.dataset.openLabel : menu.dataset.closeLabel);
      mobile.hidden = expanded;
    });
    mobile.addEventListener("click", function (event) {
      if (event.target.closest("a")) {
        mobile.hidden = true;
        menu.setAttribute("aria-expanded", "false");
        menu.setAttribute("aria-label", menu.dataset.openLabel);
      }
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && !mobile.hidden) {
        mobile.hidden = true;
        menu.setAttribute("aria-expanded", "false");
        menu.setAttribute("aria-label", menu.dataset.openLabel);
        menu.focus();
      }
    });
  }
  // Hide the bar while scrolling down; bring it back on a short scroll up. It stays visible
  // near the top, while the mobile menu is open, and while a header control has focus.
  var header = document.querySelector(".site-header");
  if (header) {
    var lastY = window.scrollY;
    var ticking = false;
    var update = function () {
      ticking = false;
      var y = Math.max(0, window.scrollY);
      var delta = y - lastY;
      var pinned = y <= header.offsetHeight || (mobile && !mobile.hidden) || header.contains(document.activeElement);
      if (pinned) header.classList.remove("is-hidden");
      if (Math.abs(delta) < 8) return;
      if (!pinned) header.classList.toggle("is-hidden", delta > 0);
      lastY = y;
    };
    window.addEventListener("scroll", function () {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    }, { passive: true });
    header.addEventListener("focusin", function () { header.classList.remove("is-hidden"); });
  }
})();
