# Pano

A personal web browser for Apple TV (tvOS), driven by the Siri Remote.

tvOS does not ship WebKit/WKWebView as public API. Pano uses the `UIWebView` class that still exists in UIKit
at runtime, created through `NSClassFromString` (see `Pano/WebEngine.swift`). Because this is private API, the app
**cannot be submitted to the App Store**; it is meant for sideloading onto your own device with Xcode.

## Installing on an Apple TV

1. On the Apple TV: Settings → Remotes and Devices → Remote App and Devices, then pair it with Xcode on your Mac
   (both on the same network; Xcode → Window → Devices and Simulators).
2. Run `xcodegen generate` (whenever `project.yml` or the file list changes) and open `Pano.xcodeproj`.
3. Pick the Apple TV as the run destination and press Run (⌘R).
   Apps signed with a free Apple ID must be reinstalled every 7 days; with a paid developer account, once a year.

## Languages

The UI is localized into the most widely used languages plus Turkish: English, Simplified Chinese, Hindi, Spanish,
French, Arabic, Brazilian Portuguese, Russian, German, Japanese and Turkish (`Pano/Localizable.xcstrings`).
Keys are English; the system language is used by default, and Settings → Language offers an in-app override
(applied after restarting the app). Use `L("…")` / `L("… %@", value)` from `Pano/Localization.swift` for new strings.

## Design

A dark background with violet → pink accents and glass (blur) surfaces. The layered (parallax) tvOS icon and the
Top Shelf images are generated with `scripts/make-icons.py` (`python3 scripts/make-icons.py . preview.png`, requires Pillow).
The same visual language is used on the home page (greeting, clock, favicon tiles), the auto-hiding floating top bar,
the iPadOS-style cursor, the side menu panel, the tab switcher, the search screen, glass toasts and the phone remote page
(`Pano/Theme.swift`, `Pano/MenuPanel.swift`, `Pano/TabSwitcherController.swift`, `Pano/SearchController.swift`).

## Features

- **Tabs** (up to 8) with a full-screen tab switcher showing page previews; open links in a new tab; `window.open` popups
  go to a background tab. Play/Pause closes the focused tab, holding select offers more actions.
- **Session restore**: open tabs come back when the app is relaunched (tabs load on demand).
- **Search screen**: tvOS's native search layout with live suggestions (go to address, search, favorites, history).
- **Zoom**: scales the whole page (75–250%), remembered per site; plus a default zoom and text size.
- **Ad/tracker blocking** (off by default for now, toggle in Settings): ~170 ad/tracking domains are blocked through a
  `URLProtocol`, and empty ad slots are hidden with CSS.
- **Smart cursor**: grows and slows down over clickable elements; sends mouse-over events so hover menus work.
- **Reader mode**: shows the main text of an article on a large-type dark page.
- **Video site players**: clicks are forwarded into cross-origin player iframes (the WebKit1 `WebFrame` API is not bound
  by the same-origin policy). For ~12 s after a click, a video that starts playing or a `.m3u8`/`.mp4` requested over
  the network is captured and opened in the tvOS player with the right Referer/Origin headers. The menu lists all
  candidates under "Play video full screen". In-page media playback is disabled on purpose (see Stability).
  Note: this engine has no `MediaSource`; players that only use MSE (blob:) streams or DRM are not supported.
- **External subtitles**: when the player opens, the site's subtitles (`<track>`, cues loaded by the page's player,
  `.vtt`/`.srt` files requested over the network, addresses found in player configs) are collected and drawn on top
  of the video. A track in the app language is selected automatically; Windows-1254 SRTs are decoded correctly.
  The player's top bar has subtitle selection, timing offset (±0.5 / ±2 s) and appearance (size, white/yellow,
  box background). Embedded HLS subtitles in the app language are selected automatically.
- **Resume playback**: the position is saved per page *and* video when the player closes (and every 10 s). When the same
  video is opened again, a "Resume" button appears inside the player (matched by video address or duration, so other
  videos on the same page are not affected). The home page has a "Continue watching" row with progress bars.
- **Next episode**: finds the page's "next episode" link (or guesses it by incrementing the episode number in the
  address); available in the player menu, as an on-screen button in the last 2 minutes and with a 10 s countdown at the
  end. On the new page the player is found and clicked automatically.
- **Source picker**: alternative player buttons ("Source 1 / Alternative / Dubbed / data-frame…") are listed in the menu
  (only on pages that have a player).
- **Player**: speed (0.75–2×), skip (10/15/30/60 s steps, "Skip intro +85 s").
- **OpenSubtitles**: player → Subtitles → Find online. API key in Settings (opensubtitles.com/consumers), optional sign-in.
  The movie/series name and season/episode are parsed from the page title; searches use the app language.
- **Phone control**: Menu → Phone control (QR). A small PIN-protected web server runs on the Apple TV on port `8765`;
  from the phone you can send addresses/searches, type into the selected field, move the cursor and scroll with a touch
  pad, and use back/home/menu/play-pause.
- **Find on page**: highlights all matches, step through them with ◀ ▶.
- **Favorites**: add, delete, rename, edit the address, reorder.
- **History**: list, search, clear.
- **Private browsing**: no history/session is saved; on exit (or relaunch) cookies are restored to their earlier state.
- Desktop/mobile sites (the real user agent is set on the inner `WebView`), search engine, cursor speed.

## Stability and performance

- **WebThread layout guard** (`Pano/LayoutGuard.swift`): legacy WebKit commits Core Animation transactions on its own
  thread, which can lay out the whole window. Auto Layout views laid out off the main thread crash on recent tvOS, so
  non-WebKit views defer such layout passes to the main thread.
- In-page media playback is disabled (`mediaPlaybackRequiresUserAction`, `play()` only records a request); WebKit's own
  video UI on tvOS could touch UIKit from the WebThread. `crossorigin` is stripped from media elements because a CORS
  failure on such a video crashes the legacy engine.
- JavaScript runs without a JIT on the device (an in-process web view cannot get the JIT entitlement), so script-heavy
  sites are slower than on a computer; mobile site view helps. The shared `URLCache` is raised to 64 MB / 512 MB.

## Remote

| Action | Result |
|---|---|
| Swipe on the touch surface | Move the cursor (pushing it to the edge scrolls the page) |
| Click | Click under the cursor; text fields open the keyboard, selects open a picker, videos open full screen |
| Hold the select button | Menu |
| Play/Pause | Cursor ↔ scroll mode |
| Double-press Play/Pause | Address / search screen |
| Hold Play/Pause | Tabs |
| Arrow buttons | Scroll the page (◀ ▶ move between matches while finding) |
| Menu / Back | Close find highlights / reader mode → previous page → home page → exit |

## Debug launch arguments (DEBUG builds only)

- `-openURL <address>`: open this address at launch
- `-hasSeenHelp YES`: skip the help dialog
- `-debugClickX <x> -debugClickY <y> [-debugType <text>]`: click that point after 3 s (and type/submit into the field)
- `-debugAction <action> [-debugDelay <s>]`: `remote`, `next`, `sources`, `subs`, `reader`, `find:word`, `zoom:150`,
  `menu`, `tabs`, `settings`, `newtab:<address>`, `private`, `hover:x,y`, `play`, `ua`, `videos`, `blocked`,
  `jsbench`, `closefocused`
- Debug builds also expose `GET http://<apple-tv>:8765/debug/{jsbench,open?url=,perf}` for on-device measurements.
