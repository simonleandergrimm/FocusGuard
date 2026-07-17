const FOCUSGUARD_ORIGIN = "http://127.0.0.1:8765";
const pendingTabs = new Set();

async function blockedStatus(hostname) {
  if (!hostname || ["127.0.0.1", "localhost"].includes(hostname)) {
    return { blocked: false };
  }
  const response = await fetch(
    `${FOCUSGUARD_ORIGIN}/api/check?host=${encodeURIComponent(hostname)}`,
    { cache: "no-store" }
  );
  if (!response.ok) return { blocked: false };
  return response.json();
}

async function redirectIfBlocked(tabId, url) {
  if (tabId < 0 || pendingTabs.has(tabId)) return;
  let destination;
  try {
    destination = new URL(url);
  } catch {
    return;
  }

  if (!["http:", "https:"].includes(destination.protocol)) {
    return;
  }
  if (["127.0.0.1", "localhost"].includes(destination.hostname)) {
    return;
  }

  try {
    const status = await blockedStatus(destination.hostname);
    if (!status.blocked) return;

    pendingTabs.add(tabId);
    await chrome.tabs.update(tabId, {
      url: `${FOCUSGUARD_ORIGIN}/blocked?host=${encodeURIComponent(destination.hostname)}`
    });
  } catch {
    // The hosts-file enforcement remains active if the local helper is unavailable.
  } finally {
    pendingTabs.delete(tabId);
  }
}

chrome.webNavigation.onBeforeNavigate.addListener(async (details) => {
  if (details.frameId !== 0) return;
  await redirectIfBlocked(details.tabId, details.url);
});

chrome.webNavigation.onHistoryStateUpdated.addListener(async (details) => {
  if (details.frameId !== 0) return;
  await redirectIfBlocked(details.tabId, details.url);
});

chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab.url) await redirectIfBlocked(tabId, tab.url);
  } catch {
    // The tab may have closed before Chrome returned it.
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "focusguard.checkHost") return false;

  blockedStatus(message.host)
    .then(sendResponse)
    .catch(() => sendResponse({ blocked: false }));
  return true;
});
