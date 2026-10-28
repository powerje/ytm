# ytm

YouTube Music in the terminal. Search for songs, artists, albums and playlists, play them through a queue with keyboard shortcuts, and continue with radio when the queue runs out.

Written in Swift for macOS. Audio is played by [mpv](https://mpv.io) with streams resolved by [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Install

Requirements: macOS 14 or later, Xcode (or the Command Line Tools), [Homebrew](https://brew.sh), and [just](https://github.com/casey/just).

```sh
brew install mpv yt-dlp just
git clone <this repository> ytm && cd ytm
just install            # builds a release binary and copies it to ~/.local/bin/ytm
ytm doctor              # checks mpv, yt-dlp and stream extraction
```

Make sure `~/.local/bin` is on your `PATH`.

YouTube changes its player regularly and an outdated yt-dlp fails silently. If `ytm doctor` reports that stream extraction failed, run `brew upgrade yt-dlp`.

## Log in

Playback and search work without an account. Your liked songs and playlists need a signed-in session, which you provide by copying the request headers of your browser session once:

1. Open <https://music.youtube.com> and sign in.
2. Open the developer tools (Cmd-Option-I) and select the **Network** tab.
3. Type `youtubei` into the filter box, then click **Library** or **Explore** in YouTube Music so a request appears, and select it.
4. Right-click it and choose **Copy › Copy as cURL**.
5. Run `ytm login`, paste, and finish with an empty line.

The session is checked before it is saved. Sessions expire after a few weeks; `ytm` tells you when to log in again. `ytm logout` deletes the stored credentials, and signing out of YouTube in your browser invalidates the session itself.

## Use

```sh
ytm
```

| Key | Action |
|---|---|
| `/` | Type a search, `Enter` to run it, `Esc` to cancel |
| `1` `2` `3` `4` | Songs, artists, albums or playlists: re-runs the search, or browses your library when the search box is empty |
| `j` `k`, arrows, `d` `u`, `g` `G` | Move, page, jump to top or bottom |
| `Tab` | Switch between results and queue |
| `Enter` | Song: play now. Artist, album or playlist: replace the queue and play. In the queue: jump to that track |
| `a` | Add the selected song, artist, album or playlist to the end of the queue |
| `o` | Open an artist, album or playlist to browse its tracks |
| `L` `P` | Your liked songs, your playlists (same as `1` and `4` with an empty search) |
| `Space` | Pause and resume |
| `n` `p` | Next and previous track |
| `,` `.` / `<` `>` | Seek 10 s / 60 s |
| `-` `+` | Volume |
| `r` | Toggle radio: when the queue ends, keep playing similar music |
| `x` `C` | Remove the selected queue entry, clear the queue |
| `q` | Quit |

The keyboard's media keys (play/pause, next, previous) and the macOS Now Playing controls work while `ytm` is running, and the current track is shown in Control Center.

## Security

This project keeps third-party code to a minimum.

- The only Swift dependency is a terminal UI library, vendored into `Vendor/` at a pinned commit and reviewed in-tree. `just deps-check` fails if anything else appears. See [DEPENDENCIES.md](DEPENDENCIES.md).
- Networking, JSON, hashing and file handling use the Apple SDK only.
- mpv runs with `--no-config`, so no user configuration or scripts are loaded, and yt-dlp is run with its configuration files ignored. Nothing is downloaded or installed by `ytm` itself.
- Credentials are stored in `~/Library/Application Support/ytm-cli/auth.json`, readable only by your user (`0600`). They are sent only to `music.youtube.com`, over HTTPS, and never written to logs.
- Search and playback send no credentials at all.

## Develop

```sh
just build        # debug build
just test         # all test suites
just precommit    # format check, lint, dependency check, build, tests
just format       # rewrite sources with swift-format
```

Formatting uses `swift format` from the toolchain; linting uses [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`).

Set `YTM_TRACE=1` to get timestamped diagnostics for the player lifecycle on standard error (`YTM_TRACE=1 ytm 2>trace.log`).

`ytm debug` exposes the API client for troubleshooting, for example `ytm debug search songs daft punk` or `ytm debug play <videoId>`.

## License

MIT, see `LICENSE`. The vendored terminal UI library is MIT licensed by its author; see `Vendor/SwiftTUI/LICENSE`.
