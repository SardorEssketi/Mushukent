const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function element() {
  const listeners = {};
  const attributes = { 'aria-expanded': 'false' };
  return {
    dataset: { openLabel: 'Open menu', closeLabel: 'Close menu' },
    hidden: true,
    listeners,
    addEventListener(name, fn) { listeners[name] = fn; },
    getAttribute(name) { return attributes[name]; },
    setAttribute(name, value) { attributes[name] = value; },
    focus() { this.focused = true; },
  };
}

const toggle = element();
const menu = element();
const mobile = element();
const documentListeners = {};
const values = {};
const context = {
  document: {
    documentElement: { dataset: { theme: 'auto' } },
    querySelector(selector) { return selector === '.theme-toggle' ? toggle : menu; },
    getElementById() { return mobile; },
    addEventListener(name, fn) { documentListeners[name] = fn; },
  },
  localStorage: {
    getItem(key) { return values[key] || null; },
    setItem(key, value) { values[key] = value; },
  },
  matchMedia() { return { matches: false }; },
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'src/site.js'), 'utf8'), context);
toggle.listeners.click();
assert.equal(context.document.documentElement.dataset.theme, 'dark');
assert.equal(toggle.getAttribute('aria-pressed'), 'true');
assert.equal(values['mushukistan-site-theme'], 'dark');
toggle.listeners.click();
assert.equal(context.document.documentElement.dataset.theme, 'light');
assert.equal(toggle.getAttribute('aria-pressed'), 'false');
menu.listeners.click();
assert.equal(menu.getAttribute('aria-expanded'), 'true');
assert.equal(menu.getAttribute('aria-label'), 'Close menu');
assert.equal(mobile.hidden, false);
documentListeners.keydown({ key: 'Escape' });
assert.equal(menu.getAttribute('aria-expanded'), 'false');
assert.equal(menu.getAttribute('aria-label'), 'Open menu');
assert.equal(mobile.hidden, true);
assert.equal(menu.focused, true);
console.log('Theme and mobile menu interactions passed.');
