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
})();
