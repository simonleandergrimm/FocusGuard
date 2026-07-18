const assert = require("node:assert/strict");
const manifest = require("../BrowserExtension/manifest.json");

let navigationListener;
let historyListener;
let activatedListener;
let messageListener;
let installedListener;
let startupListener;
let alarmListener;
let tabUpdate;
let queriedTabs = [];
let createdAlarm;

global.chrome = {
  webNavigation: {
    onBeforeNavigate: {
      addListener(listener) {
        navigationListener = listener;
      }
    },
    onHistoryStateUpdated: {
      addListener(listener) {
        historyListener = listener;
      }
    }
  },
  tabs: {
    onActivated: {
      addListener(listener) {
        activatedListener = listener;
      }
    },
    async get(tabId) {
      return { id: tabId, url: "https://example.com/already-open" };
    },
    async query() {
      return queriedTabs;
    },
    async update(tabId, update) {
      tabUpdate = { tabId, update };
    }
  },
  runtime: {
    onInstalled: {
      addListener(listener) {
        installedListener = listener;
      }
    },
    onStartup: {
      addListener(listener) {
        startupListener = listener;
      }
    },
    onMessage: {
      addListener(listener) {
        messageListener = listener;
      }
    }
  },
  alarms: {
    async get() {
      return createdAlarm;
    },
    async create(name, options) {
      createdAlarm = { name, ...options };
    },
    onAlarm: {
      addListener(listener) {
        alarmListener = listener;
      }
    }
  }
};

global.fetch = async () => ({
  ok: true,
  async json() {
    return { blocked: true };
  }
});

require("../BrowserExtension/background.js");

(async () => {
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(typeof navigationListener, "function");
  assert.equal(typeof historyListener, "function");
  assert.equal(typeof activatedListener, "function");
  assert.equal(typeof messageListener, "function");
  assert.equal(typeof installedListener, "function");
  assert.equal(typeof startupListener, "function");
  assert.equal(typeof alarmListener, "function");
  assert.equal(manifest.version, "0.4.0");
  assert.ok(manifest.permissions.includes("alarms"));
  assert.deepEqual(manifest.content_scripts[0].matches, ["http://*/*", "https://*/*"]);
  assert.deepEqual(createdAlarm, {
    name: "focusguard-scan-open-tabs",
    periodInMinutes: 0.5
  });
  await navigationListener({
    frameId: 0,
    tabId: 42,
    url: "https://example.com/temptation"
  });

  assert.deepEqual(tabUpdate, {
    tabId: 42,
    update: {
      url: "http://127.0.0.1:8765/blocked?host=example.com"
    }
  });

  tabUpdate = undefined;
  await activatedListener({ tabId: 51 });
  assert.equal(tabUpdate.tabId, 51);

  tabUpdate = undefined;
  queriedTabs = [{ id: 61, url: "https://example.com/open-before-block" }];
  await installedListener();
  assert.deepEqual(tabUpdate, {
    tabId: 61,
    update: {
      url: "http://127.0.0.1:8765/blocked?host=example.com"
    }
  });

  tabUpdate = undefined;
  queriedTabs = [{ id: 62, url: "https://example.com/still-open" }];
  await alarmListener({ name: "focusguard-scan-open-tabs" });
  assert.equal(tabUpdate.tabId, 62);

  const status = await new Promise((resolve) => {
    assert.equal(
      messageListener({ type: "focusguard.checkHost", host: "example.com" }, {}, resolve),
      true
    );
  });
  assert.deepEqual(status, { blocked: true });
  console.log("Browser extension redirect test passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
