# browse

A minimal, Wayland-native web browser: one window, just the page. No URL bar,
no tabs, no status line. You open pages from the terminal and let your window
manager do the rest.

It's about 200 lines of Nim around [WebKitGTK](https://webkitgtk.org/), the
same engine surf uses, called straight from the shared libraries, so no `-dev`
packages are needed to build it. Unlike surf, it runs natively on Wayland
(no Xwayland) and doesn't die when a page's renderer crashes.

Built on and for a Pinebook Pro running postmarketOS with sway.

## Use

```
browse [-z zoom] [-u useragent] <url>
```

`example.com` is fine; `https://` is added for you.

| Keys | |
|---|---|
| Ctrl+H / Ctrl+L | back / forward |
| Ctrl+R | reload |
| Ctrl+Shift+K / J | zoom in / out |
| Ctrl+Shift+Q | reset zoom |

- Links that ask for a new window open as a new `browse` process.
- If a page's renderer crashes, it reloads once, then shows a short notice
  instead of crash-looping.
- Cookies persist in `~/.local/share/browse/`, so logins survive.
- Close windows with your window manager (e.g. Super+Shift+Q in sway).

## Build

Needs Nim and WebKitGTK 4.1 (GTK 3). On Alpine/postmarketOS:

```
apk add nim webkit2gtk-4.1
make install            # → ~/.local/bin/browse
```

For audio/video:
`apk add gst-plugins-base gst-plugins-good gst-libav`.

## Notes

- On the RK3399 (Pinebook Pro), GStreamer's stateless hardware decoders
  (`v4l2sl*dec`) fail to negotiate with WebKit and stop playback outright, so
  browse ranks them out and uses software decoding. Set
  `GST_PLUGIN_FEATURE_RANK` yourself to override.
- Not implemented: downloads, find-in-page, any UI.

## License

MIT
