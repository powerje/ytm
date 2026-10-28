# Dependencies

Everything this program runs is listed here. Adding to this list is a deliberate decision, reviewed with the checklist at the bottom.

## Swift packages

| Package | Version | License | How it is used |
|---|---|---|---|
| [SwiftTUI](https://github.com/rensbreur/SwiftTUI) | commit `537133031bc2b2731048d00748c69700e1b48185` (2024-07-09) | MIT | Terminal rendering and input. Vendored into `Vendor/SwiftTUI`; no remote packages. |

Local changes to the vendored copy, all in `Vendor/SwiftTUI/Sources/SwiftTUI`:

- `Package.swift`: the documentation plugin dependency is removed, so the package has no dependencies.
- `RunLoop/KeyEvent.swift` (new): decodes raw terminal input into key events (arrows, paging, Enter, Escape, Backspace, Tab, characters).
- `RunLoop/Application.swift`: adds `keyHandler` (a global key handler consulted before focus-based handling), `willStop` (a hook run before exit), a public `quit()`, handling of `SIGTERM` and `SIGHUP`, and `restoreTerminal()` registered with `atexit` so the terminal is restored on every exit path.
- `Drawing/Color.swift`: `Color` is marked `Sendable` so it can be used as an attributed-string attribute value.
- `RunLoop/Application.swift`: adds the `.runLoop` run-loop type, which runs the main thread's `RunLoop` so main-actor work stays on the main thread.
- `Tests/SwiftTUITests/KeyEventParserTests.swift` (new).

The documentation catalogue (`SwiftTUI.docc`) is not vendored.

## Apple SDK

Foundation (`URLSession`, `JSONSerialization`, `Process`, `FileManager`), CryptoKit (`Insecure.SHA1`, for the request signature YouTube requires), Combine (`ObservableObject`), MediaPlayer (media keys and the Now Playing panel), Darwin (sockets, termios, ioctl, signals).

## External programs

Located on `PATH`, `/opt/homebrew/bin` or `/usr/local/bin` at run time; never downloaded or installed by this program. Paths can be overridden with `YTM_MPV` and `YTM_YT_DLP`.

| Program | Minimum version | How it is used |
|---|---|---|
| [mpv](https://mpv.io) | 0.38 | Audio playback. Launched with `--no-config` and `--input-media-keys=no`, controlled over its JSON IPC socket. |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 2025.11 | Stream URL resolution, invoked by mpv's bundled `ytdl_hook` with `--ignore-config`. |
| [deno](https://deno.com) | 2.3 | Required by yt-dlp to solve YouTube's JavaScript challenge. Installed automatically by the Homebrew `yt-dlp` formula. |

Development only: `swift format` (toolchain), [SwiftLint](https://github.com/realm/SwiftLint), [just](https://github.com/casey/just).

## Network endpoints

All requests go to `https://music.youtube.com/youtubei/v1/` (`search`, `browse`, `next`). Media is fetched by mpv from Google's video servers.

## Checklist for changing a dependency

1. Prefer the Apple SDK. A new Swift package must be vendored, pinned to a commit, and read in full.
2. Record the commit, license and every local modification above.
3. `just deps-check` must still report only the vendored UI package.
4. For external programs, bump the minimum version here and in `ytm doctor` if a newer feature is relied on.
