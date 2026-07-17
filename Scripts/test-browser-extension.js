const assert = require("node:assert/strict");
const manifest = require("../BrowserExtension/manifest.json");

let navigationListener;
let historyListener;
let activatedListener;
let messageListener;
let tabUpdate;

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
    async update(tabId, update) {
      tabUpdate = { tabId, update };
    }
  },
  runtime: {
    onMessage: {
      addListener(listener) {
        messageListener = listener;
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
  assert.equal(typeof navigationListener, "function");
  assert.equal(typeof historyListener, "function");
  assert.equal(typeof activatedListener, "function");
  assert.equal(typeof messageListener, "function");
  assert.deepEqual(manifest.content_scripts[0].matches, ["http://*/*", "https://*/*"]);
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
