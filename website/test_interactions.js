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
const header = element();
const headerClasses = new Set();
header.offsetHeight = 80;
header.classList = {
  add(name) { headerClasses.add(name); },
  remove(name) { headerClasses.delete(name); },
  toggle(name, force) { if (force) headerClasses.add(name); else headerClasses.delete(name); },
};
header.contains = (node) => node !== undefined && node === header.focusedChild;
const windowListeners = {};
const fakeWindow = { scrollY: 0, addEventListener(name, fn) { windowListeners[name] = fn; } };
const documentListeners = {};
const values = {};
const context = {
  document: {
    documentElement: { dataset: { theme: 'auto' } },
    querySelector(selector) { return { '.theme-toggle': toggle, '.site-header': header }[selector] || menu; },
    getElementById() { return mobile; },
    addEventListener(name, fn) { documentListeners[name] = fn; },
  },
  localStorage: {
    getItem(key) { return values[key] || null; },
    setItem(key, value) { values[key] = value; },
  },
  matchMedia() { return { matches: false }; },
  window: fakeWindow,
  requestAnimationFrame(fn) { fn(); },
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

function scrollTo(y) { fakeWindow.scrollY = y; windowListeners.scroll(); }
const hidden = () => headerClasses.has('is-hidden');
scrollTo(60);
assert.equal(hidden(), false, 'bar stays while it is still in view');
scrollTo(400);
assert.equal(hidden(), true, 'bar hides while scrolling down');
scrollTo(395);
assert.equal(hidden(), true, 'a tiny scroll up is ignored');
scrollTo(380);
assert.equal(hidden(), false, 'bar returns on a short scroll up');
scrollTo(700);
assert.equal(hidden(), true);
mobile.hidden = false;
scrollTo(900);
assert.equal(hidden(), false, 'bar stays while the mobile menu is open');
mobile.hidden = true;
scrollTo(1200);
assert.equal(hidden(), true);
header.listeners.focusin();
assert.equal(hidden(), false, 'keyboard focus brings the bar back');
console.log('Header hide-on-scroll passed.');

const beacons = [];
const beaconValues = {};
const beaconContext = {
  ...context,
  localStorage: {
    getItem(key) { return beaconValues[key] || null; },
    setItem(key, value) { beaconValues[key] = value; },
  },
  location: { hostname: 'mushukistan.uz', href: 'https://mushukistan.uz/uz/', pathname: '/uz/' },
  navigator: { doNotTrack: null, userAgent: 'TestAgent/1.0', language: 'uz' },
  screen: { width: 390, height: 844 },
  Intl,
  URL,
  fetch(url, options) { beacons.push({ url, body: JSON.parse(options.body) }); return Promise.resolve(); },
};
beaconContext.document = { ...context.document, referrer: '' };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'src/site.js'), 'utf8'), beaconContext);
assert.equal(beacons.length, 1);
assert.equal(beacons[0].body.distinct_id, '$posthog_cookieless');
assert.equal(beacons[0].body.properties.$cookieless_mode, true);
assert.equal(beacons[0].body.properties.$raw_user_agent, 'TestAgent/1.0');
assert.equal(beacons[0].body.properties.$pathname, '/uz/');
assert.deepEqual(beaconValues, {}, 'beacon must not write browser storage');
console.log('Cookieless page-view beacon passed.');
