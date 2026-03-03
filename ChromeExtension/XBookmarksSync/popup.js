const DEFAULT_ENDPOINT = "http://127.0.0.1:48123/x-bookmarks/import";
const BOOKMARKS_URL = "https://x.com/i/bookmarks";
const STORAGE_KEYS = {
  endpoint: "minimaltodoEndpoint",
  replaceExisting: "minimaltodoReplaceExisting"
};

const elements = {
  endpoint: document.getElementById("endpoint"),
  replaceExisting: document.getElementById("replace-existing"),
  sync: document.getElementById("sync"),
  openBookmarks: document.getElementById("open-bookmarks"),
  checkConnection: document.getElementById("check-connection"),
  appStatus: document.getElementById("app-status"),
  statusCopy: document.getElementById("status-copy")
};

document.addEventListener("DOMContentLoaded", initialize);

async function initialize() {
  const stored = await chrome.storage.local.get([
    STORAGE_KEYS.endpoint,
    STORAGE_KEYS.replaceExisting
  ]);

  elements.endpoint.value = stored[STORAGE_KEYS.endpoint] || DEFAULT_ENDPOINT;
  elements.replaceExisting.checked = stored[STORAGE_KEYS.replaceExisting] ?? true;

  elements.endpoint.addEventListener("change", persistSettings);
  elements.replaceExisting.addEventListener("change", persistSettings);
  elements.sync.addEventListener("click", handleSync);
  elements.openBookmarks.addEventListener("click", () => chrome.tabs.create({ url: BOOKMARKS_URL }));
  elements.checkConnection.addEventListener("click", refreshConnectionState);

  await refreshConnectionState();
}

async function persistSettings() {
  await chrome.storage.local.set({
    [STORAGE_KEYS.endpoint]: elements.endpoint.value.trim() || DEFAULT_ENDPOINT,
    [STORAGE_KEYS.replaceExisting]: elements.replaceExisting.checked
  });
}

async function refreshConnectionState() {
  const endpoint = normalizedEndpoint();
  const healthURL = healthEndpointFor(endpoint);

  if (!healthURL) {
    setAppStatus("Endpoint is invalid.", "error");
    return;
  }

  try {
    const response = await fetch(healthURL, { method: "GET" });
    const payload = await response.json();

    if (!response.ok || payload.status !== "ok") {
      throw new Error(payload.message || `Health check failed (${response.status})`);
    }

    if (payload.ready) {
      setAppStatus(`App ready. ${payload.bookmarkCount || 0} bookmarks cached.`, "success");
    } else {
      setAppStatus("MinimalTodo is open but its import listener is offline.", "warning");
    }
  } catch (error) {
    setAppStatus("Cannot reach MinimalTodo. Keep the app running and try again.", "warning");
  }
}

async function handleSync() {
  const endpoint = normalizedEndpoint();

  if (!endpoint) {
    setStatusCopy("Enter a valid MinimalTodo endpoint first.", "error");
    return;
  }

  await persistSettings();
  elements.sync.disabled = true;
  elements.sync.textContent = "Syncing…";
  setStatusCopy("Collecting bookmarks from the page. Leave the X tab open until this finishes.", "neutral");

  try {
    const tab = await findBookmarksTab();

    if (!tab || !tab.id) {
      await chrome.tabs.create({ url: BOOKMARKS_URL });
      setStatusCopy("Opened your X bookmarks tab. Wait for the page to load, then click Sync now again.", "warning");
      return;
    }

    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: collectBookmarksFromPage
    });

    if (!result || !Array.isArray(result.bookmarks) || result.bookmarks.length === 0) {
      throw new Error("No bookmarks were detected on the current X bookmarks page.");
    }

    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        exportedAt: new Date().toISOString(),
        replaceExisting: elements.replaceExisting.checked,
        bookmarks: result.bookmarks
      })
    });

    const payload = await response.json().catch(() => ({}));

    if (!response.ok || payload.status !== "ok") {
      throw new Error(payload.message || `MinimalTodo rejected the import (${response.status}).`);
    }

    setStatusCopy(
      `Imported ${payload.importedCount} bookmarks into MinimalTodo. Total saved: ${payload.totalCount}.`,
      "success"
    );
    await refreshConnectionState();
  } catch (error) {
    setStatusCopy(error.message || "Sync failed.", "error");
  } finally {
    elements.sync.disabled = false;
    elements.sync.textContent = "Sync now";
  }
}

async function findBookmarksTab() {
  const bookmarkTabs = await chrome.tabs.query({
    url: [
      "https://x.com/i/bookmarks*",
      "https://twitter.com/i/bookmarks*"
    ]
  });

  if (bookmarkTabs.length > 0) {
    return bookmarkTabs[0];
  }

  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return activeTab && isBookmarksURL(activeTab.url) ? activeTab : null;
}

function normalizedEndpoint() {
  const value = elements.endpoint.value.trim() || DEFAULT_ENDPOINT;

  try {
    const url = new URL(value);
    return url.toString();
  } catch (error) {
    return "";
  }
}

function healthEndpointFor(endpoint) {
  if (!endpoint) {
    return "";
  }

  try {
    const url = new URL(endpoint);
    url.pathname = "/x-bookmarks/health";
    url.search = "";
    return url.toString();
  } catch (error) {
    return "";
  }
}

function setAppStatus(message, tone) {
  elements.appStatus.textContent = message;
  elements.appStatus.className = `status-pill status-${tone}`;
}

function setStatusCopy(message, tone) {
  elements.statusCopy.textContent = message;
  setAppStatus(message, tone);
}

function isBookmarksURL(url) {
  return typeof url === "string" && /^https:\/\/(x|twitter)\.com\/i\/bookmarks/.test(url);
}

async function collectBookmarksFromPage() {
  const bookmarksById = new Map();
  const scroller = document.scrollingElement || document.documentElement;
  const idleLimit = 3;
  const maxPasses = 18;

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function cleanText(value) {
    return (value || "").replace(/\s+/g, " ").trim();
  }

  function extractStatusMatch(article) {
    const links = article.querySelectorAll("a[href*='/status/']");

    for (const link of links) {
      const href = link.getAttribute("href") || "";
      let match = href.match(/\/([^/?#]+)\/status\/(\d+)/);

      if (match) {
        return {
          id: match[2],
          authorUsername: match[1]
        };
      }

      match = href.match(/\/i\/web\/status\/(\d+)/);

      if (match) {
        return {
          id: match[1],
          authorUsername: null
        };
      }
    }

    return null;
  }

  function extractAuthorUsername(article, fallbackUsername) {
    if (fallbackUsername && fallbackUsername !== "i") {
      return fallbackUsername.replace(/^@/, "");
    }

    const profileLinks = article.querySelectorAll("[data-testid='User-Name'] a[href^='/']");

    for (const link of profileLinks) {
      const href = link.getAttribute("href") || "";
      const match = href.match(/^\/([^/?#]+)$/);

      if (match && match[1] !== "i") {
        return match[1];
      }
    }

    return null;
  }

  function extractText(article) {
    const textNode = article.querySelector("[data-testid='tweetText']");

    if (textNode) {
      return cleanText(textNode.innerText || textNode.textContent);
    }

    return cleanText(article.innerText);
  }

  function extractCreatedAt(article) {
    const timeNode = article.querySelector("time[datetime]");
    const rawValue = timeNode ? timeNode.getAttribute("datetime") : "";

    if (!rawValue) {
      return null;
    }

    const parsed = new Date(rawValue);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }

  function collectVisibleArticles() {
    const articles = document.querySelectorAll("article");

    for (const article of articles) {
      const status = extractStatusMatch(article);

      if (!status || !status.id) {
        continue;
      }

      bookmarksById.set(status.id, {
        id: status.id,
        text: extractText(article),
        authorUsername: extractAuthorUsername(article, status.authorUsername),
        createdAt: extractCreatedAt(article)
      });
    }
  }

  for (let attempt = 0; attempt < 20; attempt += 1) {
    collectVisibleArticles();

    if (bookmarksById.size > 0) {
      break;
    }

    await sleep(500);
  }

  let idlePasses = 0;
  let previousCount = bookmarksById.size;
  let previousHeight = scroller.scrollHeight;

  for (let pass = 0; pass < maxPasses && idlePasses < idleLimit; pass += 1) {
    scroller.scrollTo({ top: scroller.scrollHeight, behavior: "auto" });
    await sleep(1400);
    collectVisibleArticles();

    const currentCount = bookmarksById.size;
    const currentHeight = scroller.scrollHeight;

    if (currentCount === previousCount && currentHeight === previousHeight) {
      idlePasses += 1;
    } else {
      idlePasses = 0;
    }

    previousCount = currentCount;
    previousHeight = currentHeight;
  }

  scroller.scrollTo({ top: 0, behavior: "auto" });

  const bookmarks = Array.from(bookmarksById.values()).sort((left, right) => {
    if (left.createdAt && right.createdAt && left.createdAt !== right.createdAt) {
      return left.createdAt < right.createdAt ? 1 : -1;
    }

    return left.id < right.id ? 1 : -1;
  });

  return {
    bookmarkCount: bookmarks.length,
    bookmarks
  };
}
