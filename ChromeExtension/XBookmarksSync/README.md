# MinimalTodo Chrome Extension

This unpacked Chrome extension scrapes the logged-in `x.com/i/bookmarks` page and posts the results to MinimalTodo's local import listener at `http://127.0.0.1:48123/x-bookmarks/import`.

## Install

1. Open `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select this folder: `ChromeExtension/XBookmarksSync`

## Use

1. Keep MinimalTodo open.
2. Open your X bookmarks page in Chrome.
3. Click the extension button.
4. Verify the endpoint is `http://127.0.0.1:48123/x-bookmarks/import`
5. Click **Sync now**

The extension uses DOM scraping, so if X changes its page structure you may need to update the selectors in `popup.js`.
