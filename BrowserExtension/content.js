const FOCUSGUARD_ORIGIN = "http://127.0.0.1:8765";
let redirecting = false;

async function checkCurrentHost() {
  if (redirecting || !["http:", "https:"].includes(location.protocol)) return;
  if (["127.0.0.1", "localhost"].includes(location.hostname)) return;

  try {
    const status = await chrome.runtime.sendMessage({
      type: "focusguard.checkHost",
      host: location.hostname
    });
    if (!status?.blocked) return;

    redirecting = true;
    location.replace(
      `${FOCUSGUARD_ORIGIN}/blocked?host=${encodeURIComponent(location.hostname)}`
    );
  } catch {
    // The hosts-file enforcement remains active if the extension is reloading.
  }
}

checkCurrentHost();
setInterval(checkCurrentHost, 3_000);
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") checkCurrentHost();
});
