## browse — a minimal Wayland-native web browser: one window, just the page.
##
## A thin shell around WebKitGTK (the engine surf uses), called straight
## from the shared libraries, so no -dev packages are needed to build it.
##
##   browse [-z zoom] [-u useragent] <url>
##
## Keys:  Ctrl+H / Ctrl+L     back / forward
##        Ctrl+R              reload
##        Ctrl+Shift+K / J    zoom in / out
##        Ctrl+Shift+Q        reset zoom
##
## Links that ask for a new window open as a new `browse` process.
## If a page's renderer crashes, the page reloads instead of the browser dying.
##
## Build: make install   (→ ~/.local/bin/browse)

import std/[os, osproc, strutils, times]

const
  libGtk     = "libgtk-3.so.0"
  libGobject = "libgobject-2.0.so.0"
  libGlib    = "libglib-2.0.so.0"
  libWebkit  = "libwebkit2gtk-4.1.so.0"

type
  GPointer = pointer
  GdkEventKey {.bycopy.} = object   # leading fields of GdkEventKey (gdk/gdkevents.h)
    typ:       cint
    window:    pointer
    sendEvent: int8
    time:      uint32
    state:     uint32
    keyval:    uint32
  GdkRGBA {.bycopy.} = object
    red, green, blue, alpha: cdouble

const
  ShiftMask   = 1'u32 shl 0
  ControlMask = 1'u32 shl 2
  CookiesSqlite = 1.cint            # WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE
  LoadFinished  = 3.cint            # WEBKIT_LOAD_FINISHED
  # Shown until the first page has loaded, so opening a window doesn't
  # flash white: the same 242424 as foot and the sway background.
  Dark  = GdkRGBA(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255, alpha: 1)
  White = GdkRGBA(red: 1, green: 1, blue: 1, alpha: 1)

# --- GLib / GObject / GTK ---------------------------------------------------
proc g_set_prgname(name: cstring) {.importc, dynlib: libGlib.}
proc g_signal_connect_data(instance: GPointer; signal: cstring; handler: pointer;
                           data: GPointer; destroy: pointer; flags: cint): culong
  {.importc, dynlib: libGobject.}
proc gtk_init(argc, argv: pointer) {.importc, dynlib: libGtk.}
proc gtk_main() {.importc, dynlib: libGtk.}
proc gtk_main_quit() {.importc, dynlib: libGtk.}
proc gtk_window_new(kind: cint): GPointer {.importc, dynlib: libGtk.}
proc gtk_window_set_default_size(w: GPointer; width, height: cint) {.importc, dynlib: libGtk.}
proc gtk_window_set_title(w: GPointer; title: cstring) {.importc, dynlib: libGtk.}
proc gtk_container_add(c, child: GPointer) {.importc, dynlib: libGtk.}
proc gtk_widget_show_all(w: GPointer) {.importc, dynlib: libGtk.}
proc gtk_widget_grab_focus(w: GPointer) {.importc, dynlib: libGtk.}
proc gtk_widget_override_background_color(w: GPointer; state: cint; c: ptr GdkRGBA)
  {.importc, dynlib: libGtk.}

# --- WebKitGTK ----------------------------------------------------------------
proc webkit_web_context_get_default(): GPointer {.importc, dynlib: libWebkit.}
proc webkit_web_context_get_cookie_manager(ctx: GPointer): GPointer {.importc, dynlib: libWebkit.}
proc webkit_cookie_manager_set_persistent_storage(cm: GPointer; file: cstring; kind: cint)
  {.importc, dynlib: libWebkit.}
proc webkit_web_view_new(): GPointer {.importc, dynlib: libWebkit.}
proc webkit_web_view_get_settings(v: GPointer): GPointer {.importc, dynlib: libWebkit.}
proc webkit_settings_set_user_agent(s: GPointer; ua: cstring) {.importc, dynlib: libWebkit.}
proc webkit_web_view_load_uri(v: GPointer; uri: cstring) {.importc, dynlib: libWebkit.}
proc webkit_web_view_load_html(v: GPointer; html, baseUri: cstring) {.importc, dynlib: libWebkit.}
proc webkit_web_view_reload(v: GPointer) {.importc, dynlib: libWebkit.}
proc webkit_web_view_set_background_color(v: GPointer; c: ptr GdkRGBA) {.importc, dynlib: libWebkit.}
proc webkit_web_view_go_back(v: GPointer) {.importc, dynlib: libWebkit.}
proc webkit_web_view_go_forward(v: GPointer) {.importc, dynlib: libWebkit.}
proc webkit_web_view_get_zoom_level(v: GPointer): cdouble {.importc, dynlib: libWebkit.}
proc webkit_web_view_set_zoom_level(v: GPointer; z: cdouble) {.importc, dynlib: libWebkit.}
proc webkit_web_view_get_title(v: GPointer): cstring {.importc, dynlib: libWebkit.}
proc webkit_web_view_get_uri(v: GPointer): cstring {.importc, dynlib: libWebkit.}
proc webkit_navigation_action_get_request(a: GPointer): GPointer {.importc, dynlib: libWebkit.}
proc webkit_uri_request_get_uri(r: GPointer): cstring {.importc, dynlib: libWebkit.}

# --- state ----------------------------------------------------------------------
var
  window, view: GPointer
  defaultZoom = 1.0
  userAgent = ""
  lastCrash: Time

proc openInNewBrowser(uri: string) =
  ## New-window links become their own `browse` process, same settings.
  var args = @["-z", $defaultZoom]
  if userAgent.len > 0: args.add ["-u", userAgent]
  args.add uri
  discard startProcess(getAppFilename(), args = args, options = {poDaemon})

# --- signal handlers --------------------------------------------------------------
proc onDestroy(w, data: GPointer) {.cdecl.} = gtk_main_quit()

proc onTitle(obj, pspec, data: GPointer) {.cdecl.} =
  let t = webkit_web_view_get_title(view)
  gtk_window_set_title(window, if t.isNil or t[0] == '\0': cstring"browse" else: t)

proc onLoad(v: GPointer; event: cint; data: GPointer) {.cdecl.} =
  # Pages that don't set a background expect white, so switch once one is in.
  if event == LoadFinished:
    var c = White
    webkit_web_view_set_background_color(view, addr c)

proc onCreate(v, action, data: GPointer): GPointer {.cdecl.} =
  let uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action))
  if not uri.isNil and uri[0] != '\0': openInNewBrowser($uri)
  nil                                   # don't let WebKit make a window itself

proc onCrash(v: GPointer; reason: cint; data: GPointer) {.cdecl.} =
  # Reload once; if it crashes again within 10 s, stop and say so.
  if getTime() - lastCrash > initDuration(seconds = 10):
    lastCrash = getTime()
    webkit_web_view_reload(view)
  else:
    let uri = $webkit_web_view_get_uri(view)
    webkit_web_view_load_html(view, cstring(
      "<body style='font:16px sans-serif;background:#242424;color:#ddd;padding:2em'>" &
      "<p>This page keeps crashing the renderer.</p><p style='color:#888'>" & uri &
      "</p><p>Ctrl+R to try again.</p></body>"), nil)

proc onKey(w: GPointer; ev: ptr GdkEventKey; data: GPointer): cint {.cdecl.} =
  if (ev.state and ControlMask) == 0: return 0
  let shift = (ev.state and ShiftMask) != 0
  let key = char(ev.keyval and 0xff).toLowerAscii
  if ev.keyval > 0xff: return 0
  case key
  of 'h': webkit_web_view_go_back(view)
  of 'l': webkit_web_view_go_forward(view)
  of 'r': webkit_web_view_reload(view)
  of 'k':
    if not shift: return 0
    webkit_web_view_set_zoom_level(view, webkit_web_view_get_zoom_level(view) + 0.1)
  of 'j':
    if not shift: return 0
    webkit_web_view_set_zoom_level(view, max(0.3, webkit_web_view_get_zoom_level(view) - 0.1))
  of 'q':
    if not shift: return 0
    webkit_web_view_set_zoom_level(view, defaultZoom)
  else: return 0
  1                                     # handled: don't pass to the page

# --- main ----------------------------------------------------------------------------
proc usage() =
  quit "usage: browse [-z zoom] [-u useragent] <url>", 1

var url = ""
let args = commandLineParams()
var i = 0
while i < args.len:
  case args[i]
  of "-z", "-u":
    if i + 1 >= args.len: usage()
    if args[i] == "-z":
      try: defaultZoom = parseFloat(args[i + 1])
      except ValueError: usage()
    else: userAgent = args[i + 1]
    i += 2
  else:
    if args[i].startsWith("-"): usage()
    url = args[i]
    inc i
if url.len == 0: usage()
if "://" notin url and not url.startsWith("about:"): url = "https://" & url

# The RK3399's stateless hardware decoders (v4l2codecs) fail to negotiate
# with WebKit and kill playback instead of falling back, so rank them out;
# GStreamer then uses software decoding (avdec_* from gst-libav).
# Set GST_PLUGIN_FEATURE_RANK yourself to override.
if not existsEnv("GST_PLUGIN_FEATURE_RANK"):
  putEnv("GST_PLUGIN_FEATURE_RANK",
    "v4l2slh264dec:NONE,v4l2slh265dec:NONE,v4l2slvp8dec:NONE,v4l2slvp9dec:NONE,v4l2slmpeg2dec:NONE")

g_set_prgname("browse")                 # names the data dir and the Wayland app_id
gtk_init(nil, nil)

# Persistent cookies, so logins survive closing the window.
let dataDir = getEnv("XDG_DATA_HOME", getHomeDir() / ".local/share") / "browse"
createDir(dataDir)
webkit_cookie_manager_set_persistent_storage(
  webkit_web_context_get_cookie_manager(webkit_web_context_get_default()),
  cstring(dataDir / "cookies.sqlite"), CookiesSqlite)

window = gtk_window_new(0)              # GTK_WINDOW_TOPLEVEL
gtk_window_set_default_size(window, 1200, 800)
gtk_window_set_title(window, "browse")
view = webkit_web_view_new()
if userAgent.len > 0:
  webkit_settings_set_user_agent(webkit_web_view_get_settings(view), cstring(userAgent))
webkit_web_view_set_zoom_level(view, defaultZoom)
var dark = Dark
gtk_widget_override_background_color(window, 0, addr dark)   # GTK_STATE_FLAG_NORMAL
webkit_web_view_set_background_color(view, addr dark)
gtk_container_add(window, view)

discard g_signal_connect_data(window, "destroy", onDestroy, nil, nil, 0)
discard g_signal_connect_data(window, "key-press-event", onKey, nil, nil, 0)
discard g_signal_connect_data(view, "notify::title", onTitle, nil, nil, 0)
discard g_signal_connect_data(view, "load-changed", onLoad, nil, nil, 0)
discard g_signal_connect_data(view, "create", onCreate, nil, nil, 0)
discard g_signal_connect_data(view, "web-process-terminated", onCrash, nil, nil, 0)

webkit_web_view_load_uri(view, cstring(url))
gtk_widget_show_all(window)
gtk_widget_grab_focus(view)
gtk_main()
