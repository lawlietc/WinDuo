# WinDuo

[简体中文](../README.md) | **English**

<p align="center">
  A lightweight Windows tool that turns "drag into the left / right half of the screen" into a real half-screen snap.
</p>

WinDuo is a single-file [AutoHotkey v2](https://www.autohotkey.com/) script: drag a window to either side of the screen and release, and it snaps to that half. Newly opened windows can also be placed automatically into whichever half is free, according to the strategy you pick. No network access, no polling, no low-level keyboard/mouse hooks, nothing drawn on screen.

## Features

- **Drag to snap** — drag a window into the left or right half of the work area and release; it fits that half exactly. Position is set directly with `SetWindowPos` instead of synthesising Win+Arrow, so it is unaffected by the OS "Snap windows" setting and never throws a window onto another monitor.
- **Automatic placement of new windows** — a window that just opened is placed into the free half. Two strategies (switchable at any time from the tray menu; the choice is remembered):
  - **Auto**: use whichever half is free; when both are full, evict the column that was used least recently ("least recently used" is derived from two per-column timestamps maintained by `EVENT_FOREGROUND`).
  - **Follow cursor**: cursor on the left puts the window on the left column (same-side), or the inverted opposite-side variant. This path is decided purely by the cursor position and ignores occupancy.
  - Placement only targets windows that "look like a document window": a title-bar style, a non-empty title, not cloaked by DWM (i.e. not on another virtual desktop),
    not a tool window, not maximised, and not already snapped to either half — fail any one of those and it is skipped, with the reason written to the log (`skip:cloaked`, etc.).
- **Multi-monitor aware** — the half is computed from the work area of the monitor under the cursor, handling the taskbar and left/right docked toolbars correctly.
- **UI language follows the system** — tray menu, tooltip, error box, and the `[exclude]` help block generated into `WinDuo.ini` are in Chinese on a Chinese system and in English everywhere else (detection details in the "UI language" section).
- **Excluded programs** — an exe on the list is handed back to the system entirely: no drag-snap, no automatic placement, and it does not count as occupying a half (configuration below).
- **Excluded popups (on by default, zero configuration)** — dialogs and copy/delete progress boxes, which are "not document windows by nature", are recognised automatically and skipped. Without this, an Explorer "Confirm delete" dialog would get thrown onto a half screen and look absurd. Criteria in the "Popup detection" section; override with `!app.exe`.
- **Move vs resize** — distinguished by cursor shape (the same approach FancyZones uses), so dragging a window you already snapped is not mistaken for a resize.
- **Aligned to the DWM visible frame** — `DwmGetWindowAttribute` supplies the visible border rather than the window rect, so the result fills the half exactly on screen with no invisible shadow margin left showing.
- **Never fights the user** — while you are manually dragging a window, the delayed re-check of automatic placement backs off.

## Requirements

- Windows 10 / 11
- [AutoHotkey v2](https://www.autohotkey.com/download/) (v2.0 or newer; first line of the script is `#Requires AutoHotkey v2.0`)
- Running the packaged `Release\WinDuo.exe` needs no AutoHotkey installation (the interpreter base is embedded in the exe)

## Quick start

1. Install AutoHotkey v2.
2. Double-click `WinDuo.ahk` (or run `node build.js` and double-click the resulting `Release\WinDuo.exe`).
3. A tray icon appears (tooltip "WinDuo is running"). Right-click it for:
   - **Placement** — three submenu items, the active one ticked:
     `Auto: use the free half; when both are taken, evict the least recently used column` / `Follow cursor: cursor on the left puts the window on the left` / `Follow cursor: cursor on the left puts the window on the right`;
     the choice is written to the `[WinDuo]` section of `WinDuo.ini` (`placeMode` / `cursorInvert`) and survives a restart;
   - **Excluded apps** — opens `WinDuo.ini` with whatever the system has associated (no editor is hardcoded); save and it takes effect immediately.
     Clicking it appends a `open-ini <path> ret=<n>` line to the log: only `ret` greater than 32 means a program actually launched,
     anything ≤ 32 is a `SE_ERR_*` code (2 = file not found, 31 = no app associated with `.ini`) —
     if nothing appears to happen, read that line instead of guessing;
   - **Open log** — shows `%TEMP%\WinDuo.log`;
   - **Exit WinDuo**.

Start on boot: press `Win+R`, type `shell:startup`, and drop a shortcut to `WinDuo.ahk` (or `WinDuo.exe`) in there.
Launching it again replaces the old instance outright (`#SingleInstance Force`), so you never get two WinDuos fighting over the same window.

### UI language

What is read is the **system UI language** (the primary-language bits of `GetUserDefaultUILanguage`): `0x04`
(zh-CN / zh-TW / zh-HK all share this primary code) shows Chinese, every other language shows English. The regional
format is not consulted — using `GetUserDefaultLangID` would report Chinese on a machine whose UI is English but whose
regional format is China, which is why the UI-language API is the one used.

- Translated: the four tray menu items plus the three placement sub-items, the tray tooltip, the error box shown when
  `SetWinEventHook` fails, the `[exclude]` help block `EnsureExcludeSection` appends to the ini, and two purely
  explanatory log strings (the `exclude reject` hint and the `open-ini` failure reason).
- Not translated: the verdict lines in the log (`start` / `show` / `end`, `skip:excluded`, `snap L ok=1`) and the
  identifiers in the ini (`placeMode` / `cursorInvert` / `[exclude]` / `class:`). The former are machine-readable
  tokens meant to be grepped — the assertions in `test/*.js` are written against them; the latter are configuration
  keys that would stop parsing if translated.
- All wording lives in one table at the top of the script, `TXT := Map(key -> [Chinese, English])`, and is only ever
  fetched through `T(key)`. Add new wording to the table; hardcoding a string at a call site will always miss the
  other language.
- The `lang=zh` / `lang=en` line written at startup is the evidence for "why this language this time".
- Verify with `node test/lang_check.js` — it pins `IS_ZH` to true and false, runs once per language and asserts both
  wording sets (the English pass also asserts no CJK characters appear at all), then does a final unmodified run to
  confirm this machine picked the right set.

## Behaviour

| Action | Result |
|--------|--------|
| Drag a window, cursor in the left half at release | window snaps to the left half |
| Drag a window, cursor in the right half at release | window snaps to the right half |
| Open a new window | placed automatically per the strategy chosen in the tray |
| Drag a maximised window | not handled (avoids clashing with the OS drag-to-restore behaviour) |
| Drag while the cursor is a resize handle | not handled (that is a resize, not a move) |
| Drag / open a program listed in `[exclude]` | not handled, left entirely to the system |
| Open a dialog / file-operation progress box (default) | no snap, no placement, does not occupy a half |
| Open a window with no title bar / no title text / a tool window / cloaked on another virtual desktop | not placed, does not occupy a half |
| Open a window already snapped to one of the halves | not moved again |
| Window already exactly equal to the target half at release | left alone (log: `skip:already`) |

## Configuration

Most behaviour parameters live in the `CONFIG` object at the top of the script (changing them requires a restart — only the `[exclude]` section hot-reloads):

| Key | Default | Description |
|-----|---------|-------------|
| `snapTolerance` | `3` | pixel tolerance for "already on the target half" |
| `occupiedTolerance` | `24` | pixel tolerance for "this half is occupied" |
| `minDrag` | `20` | cursor travel below this is treated as an accidental click and dropped |
| `settleDelay` | `60` | milliseconds to let the system finish after release |
| `autoPlace` | `true` | whether new windows are placed automatically |
| `placeDelay` | `40` | delay after a new window appears before placing it |
| `verifyDelay` | `150` | delay before re-checking the placement (some apps push the window back themselves) |
| `verifyAttempts` | `2` | maximum number of moves; `1` = move once, never re-check |
| `placeMode` | `"auto"` | placement mode: `auto` / `cursor` (rewritten by the tray menu) |
| `cursorInvert` | `false` | only meaningful in `cursor` mode: same side `false` / opposite side `true` (rewritten by the tray menu) |
| `popupGuard` | `true` | whether popups are detected and excluded automatically (see "Popup detection") |
| `debug` | `true` | whether the decisions are written to `%TEMP%\WinDuo.log` |

Persistent settings live in `WinDuo.ini` next to the script (UTF-16, created and rewritten by the script itself). What follows is exactly what the script generates — when the `[exclude]` section is missing it appends the help comment block so there is somewhere to write as soon as the file opens; only the last four lines are user-added rules:

```ini
[WinDuo]
placeMode=cursor
cursorInvert=1

[exclude]
; One rule per line. Takes effect on save, no restart needed
;   app.exe             leave this program alone (case-insensitive, the .exe is required)
;   class:WndClass      leave this window class alone in every program
;   app.exe|WndClass    leave this class alone only in this program
;   !app.exe            exempt this program from the built-in popup detection below
; A semicolon mid-line starts a comment and everything after it is dropped. A rule
; without .exe is not registered; the log gets one exclude reject line instead
; Dialogs and file-operation progress boxes are detected on their own and left alone
foobar2000.exe
class:OperationStatusWindow
explorer.exe|#32770
!Calculator.exe
```

The four rule forms in `[exclude]` (all bare lines, no key):

| Form | Meaning |
|------|---------|
| `app.exe` | matches the **executable file name of the process**, case-insensitive, compared with `.exe` stripped; the `.exe` must be written in full |
| `class:WndClass` | matches the window class (`GetClassNameW`), across every process, no `.exe` |
| `app.exe\|WndClass` | requires both to match — for the case where one class name means different things in different programs |
| `!app.exe` | exempts the program from the **built-in popup detection** only; hand-written rules still apply |

When any rule matches: no drag-snap, no automatic placement, and the window does not participate in the "which half is occupied" decision — it should not influence where other windows get put.

- Takes effect on save, no restart (the script detects edits from the file's timestamp plus size).
- Everything after a mid-line `;` is dropped, so `foobar2000.exe   ; music player` is a safe way to write it; a comment on its own line works too.
  The price is that **`;` may not appear in a program name or window class** (`;` is already illegal in Windows file names; only a handful of custom window classes trip over it).
- A rule without `.exe` **is not registered**; the log gets one `exclude reject: <verbatim line>` — better to be loud than to let a mistyped list silently do nothing.
  Previously the short form worked by having `NormExe` strip the extension before comparing against `WinGetProcessName`, and that stripping step was once written wrong (`SubStr(n, -3)`),
  which silently disabled every rule written without `.exe`. Writing the name in full is now mandatory, so the name in the file is the process's actual file name.
- After editing, look for the `exclude reloaded: <rule>` line in the log — that is what the script actually registered.
- A line containing `=` is treated as `key=value` and skipped outright (so `=` cannot appear in a rule); a line starting with `[` is treated as a section header and skipped.
- The scan covers the **whole file**, so a rule works no matter which section follows it; putting it under `[exclude]` merely protects it from being wiped by `IniWrite` (which only touches `[WinDuo]`).
- Do not save this file as UTF-8: the Win32 ini parser fails on the entire file when it meets a UTF-8 BOM (not even `placeMode` survives it),
  and `IniWrite` / the script's own rewrites always use UTF-16. So "open in Notepad → edit → save as ANSI/UTF-8" is a broken path —
  save as the system-default UTF-16, or simply only add lines inside the `[exclude]` section.
- The `[exclude]` section is scanned line by line by the script itself; `IniRead` cannot see bare lines (the Win32 ini API only understands `key=value`), so don't try to read it through an ini API.

### Popup detection

No rules needed — the following window kinds are excluded by default, because an experience like "delete a file in a folder and the confirmation dialog gets flung onto a half screen" should not require the user to learn the configuration first:

| Criterion | What it catches |
|-----------|-----------------|
| window class `#32770` | standard dialogs / TaskDialogs: delete confirmation, overwrite confirmation, property sheets, Save As… |
| window class `OperationStatusWindow` | shell file-operation progress box (the one shown during copy / move / delete) |
| `WS_EX_DLGMODALFRAME` style bit | dialogs carrying a modal frame (also catches toasts, `#32768`) |
| has an owner + absent from the taskbar + not resizable | small accessory popups drawn by frameworks themselves |

The first two **must** match on class name — there is no way out at the style level (measured data in `../test/README.md`):

- The copy progress box (`OperationStatusWindow`) **is resizable, has a minimise button and has no owner** — its style is indistinguishable from a normal main window.
  The most tempting criterion, "ignore anything without a maximise button", would sweep those windows up as collateral damage — AHK's own `Gui()`
  and a large number of fixed-size tool windows have no maximise button either.
- Conversely, delete / overwrite confirmation dialogs have very distinct style features (`WS_POPUP` + no min/max buttons + modal frame),
  but the class-name check already covers them, so there is no need to rely on styles.

If one of your own main windows gets caught (a few old programs build the main window as `#32770`), add a `!app.exe` line to `[exclude]` to release it.
Every verdict in the log carries its reason, so no guessing is involved.

## Troubleshooting

The log is written to `%TEMP%\WinDuo.log` (nothing is written when `CONFIG.debug` is off); open it straight from the tray's "Open log". One action plus one reason per line,
and a window is identified only as `hwnd [class]` (the title is never logged — see "Implementation notes").

| Prefix | Where it appears | Meaning |
|--------|------------------|---------|
| `start skip:excluded` / `excluded:class` / `excluded:app\|class` | drag start press | a hand-written `[exclude]` rule matched |
| `start skip:popup:#32770` / `popup:operationstatuswindow` / `popup:modal` / `popup:owned` | drag start press | built-in popup detection matched (one line per criterion) |
| `start skip:maximized` | drag start press | the window is maximised |
| `start skip:resize` | drag start press | the cursor is a resize handle — a resize, not a move |
| `end skip:too-small dx=.. dy=..` | release | travel below `minDrag`, discarded as an accidental click |
| `end skip:busy` | release | automatic placement is moving another window, so this one backs off |
| `end skip:already` | release | already flush with the target half (within `snapTolerance`), left alone |
| `end skip:no-start` | release | only END arrived, no START (the start was blocked by one of the skips) |
| `end snap L/R ok=1` | release | drag-snap completed |
| `show skip:invisible/cloaked/maximized/toolwindow/no-text/same-half` | new window appears | not a document window, or already snapped to a half |
| `show snap L/R ok=` / `show cursor L/R ok=` / `show replace L/R ok=` | new window placement | the three outcomes: fill the free half / follow cursor / evict a column |
| `       occupied by hwnd [class]` | occupancy scan | which window is considered to hold a given half — shows directly why nothing was placed there |
| `exclude reloaded: <rule>` | any event | `[exclude]` was edited externally and reloaded (only what is listed is in effect) |
| `exclude reject: <verbatim line>` | loading `[exclude]` | this rule was rejected (program name missing `.exe`) — the only trace a bad list leaves behind |
| `mode -> cursor invert=1` | tray switch | placement mode changed and written to the ini |
| `open-ini <path> ret=<n>` | tray "Excluded apps" | `ret<=32` means nothing launched (2 = file not found, 31 = no app associated with `.ini`) |
| `ERROR[move/show/fg/global] ...` | outside a callback | the exception was swallowed by `try/catch` and only logged; the script keeps running |

Windows with no title-bar style are dropped by the cheap prefilter in `OBJECT_SHOW` and never get a line at all (that event fires far too often — filter first, then arm a one-shot timer).
The log is pure append with no rotation; delete the file when it grows too long and the script recreates it on the next write. It is written in the system ANSI code page (`FileAppend`'s default),
so Notepad shows it fine, but if your rules contain Chinese comments, opening it in a UTF-8 editor gives mojibake — that mojibake is not the script misreading the ini, it is the wrong viewer for the log.

Line numbers in errors from the compiled exe are those of **the script embedded in the build output**, not of the `.ahk` source — Ahk2Exe strips comments and blank lines,
so re-apply the same filtering to map them back.

## Implementation notes

- All events come from `SetWinEventHook` (`MOVESIZESTART/END`, `OBJECT_SHOW`, `FOREGROUND`), out-of-context:
  no polling, no global hooks; all three hooks carry `WINEVENT_SKIPOWNPROCESS`, so WinDuo's own windows never reach the callbacks.
- `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` is called before the hooks are installed: the half-screen rect is computed straight from the work-area pixels returned by `GetMonitorInfoW`,
  and if the process does not declare DPI awareness the system virtualises our coordinates — at anything other than 100% scaling the computed half boundary no longer matches reality, leaving a gap between the two halves or throwing the window onto a neighbouring monitor.
- `OBJECT_SHOW` fires a lot, so an extremely cheap prefilter ("does it have a title-bar style") runs first, and only then is a one-shot timer armed.
- Half occupancy is decided by "edge touching edge", not overlap area — a large centred window easily overlaps one half by more than 50%, which would produce false positives.
- When both halves are full, which column gets evicted follows two timestamps maintained by `EVENT_FOREGROUND` (the last `GetTickCount64` at which each column was activated);
  the smaller timestamp loses. When both are 0 (script just started) the left column is preserved.
- Top-level windows are walked with `GetWindow(GW_CHILD / GW_HWNDNEXT)` rather than `EnumWindows`: measured with a shell file-operation dialog open, `EnumWindows` wedges the caller
  (it does cross-thread work internally) — and the "place a new window" path is precisely the moment a file-operation dialog appears.
- The APIs used for the decisions are predominantly local calls (`GetClassNameW` / `GetWindowLong` / `GetWindow` / `WinGetProcessName`);
  fetching full titles is deliberately avoided — that sends `WM_GETTEXT` cross-process, and a hung target would drag our hook callback down with it.
  The "does it have a title" check on the new-window path uses `GetWindowTextLengthW`: cross-process it still sends `WM_GETTEXTLENGTH`,
  but it returns a single integer instead of copying a string, so the risk of being stalled is an order of magnitude lower — and it removes the collateral damage of "frameless untitled windows get placed too".
- Windows are moved with `SetWindowPos`, `hWndInsertAfter = HWND_TOP` plus `SWP_NOACTIVATE`: when evicting a column the new window is not left underneath the old one,
  and focus is not stolen. The rect applied is the *visible* frame, so the invisible-border delta is first read from `DwmGetWindowAttribute` and compensated for.
- Shell windows (`Progman` / `WorkerW` / the taskbar and friends) are excluded, since they cover the whole screen and would make both halves permanently "occupied".
- The log records the window class and never the title: same reason as two bullets above.
- Any uncaught exception goes to the log instead of a dialog that would freeze the script (`OnError` plus a `try/catch` around every callback).
- A parsing hazard when editing the script: inside an expression **continuation** line (the kind starting with `.`), a string containing "space + `;`" produces
  `Missing "` immediately — `"; comments may start ; here"` fails, while a full-width semicolon or a `;` placed right against the quote is fine.
  The block `EnsureExcludeSection` generates for `[exclude]` sits exactly on that line, so never put an ASCII semicolon back into those strings.
- Syntax is validated by compiling (Ahk2Exe returns 0 on success, 17 on failure and prints `Missing "` plus a line number to stderr); `AutoHotkey64.exe /validate`
  hangs on this machine and cannot serve as a gate — `test/compile.js` uses the compiler as the syntax checker.

## Comparison

|  | WinDuo | Built-in Windows Snap |
| :-- | :-- | :-- |
| Footprint | single-file script, ~39 KB / 1038 lines | part of the OS |
| Snaps when dragged into a half | ✅ | requires hitting the top / side edge |
| New windows placed automatically | ✅ | ❌ |
| Exclude apps by exe name | ✅ | ❌ (snap can only be switched off wholesale) |
| Exclude by window class / popups excluded by default | ✅ | ❌ (confirmation dialogs get snapped anyway) |
| Independent of the "Snap windows" setting | ✅ | — |
| No drawing / no network | ✅ | ✅ |

## Building the exe

Use the `build.js` in this repository (`node build.js`); what it runs is:

```
Ahk2Exe /in WinDuo.ahk /out Release\WinDuo.build.exe /bin <install dir>\v2\AutoHotkey64.exe /icon assets\WinDuo.ico /silent
```

The AutoHotkey install directory defaults to `%LOCALAPPDATA%\Programs\AutoHotkey`; set the `AHK_DIR` environment variable if it lives elsewhere.
The script also: aborts with an error if `WinDuo.exe` is running (otherwise Ahk2Exe gets stuck in a dialog), builds to
`Release\WinDuo.build.exe` and only renames it over `Release\WinDuo.exe` once that succeeds (so a failed build cannot destroy the last working artefact),
and reads the PE header to confirm `machine == 0x8664` (the file may not be fully flushed once Ahk2Exe exits — the first few reads see an all-zero PE header, hence the retry with delays).
The artefact is about 1.24 MB (base + embedded script + icon).

- **`/bin` must explicitly point at `AutoHotkey64.exe`.** Without that argument Ahk2Exe uses the 32-bit base, and the
  `SetWinEventHook` callback reads window styles: the `GetWindowLongPtrW` export **exists only in the 64-bit user32**
  (it is a macro in the C/C++ headers, whereas `DllCall` looks exports up by name at runtime and throws
  `Call to nonexistent function.` when it finds nothing). The exception is swallowed by the `try/catch` outside the callback and only logged,
  so the symptom becomes "drag-snap works, automatic placement silently doesn't". (The script now selects
  `GetWindowLongPtrW` / `GetWindowLongW` by `A_PtrSize`, so both bitnesses work; the build still always emits a 64-bit artefact.)
- Only **one** package is needed: 64-bit. WOW64 runs 32-bit programs on 64-bit Windows but not the other way round, and every machine WinDuo targets is 64-bit —
  shipping two packages would only turn "downloaded the wrong one" into a class of bug.
- Ahk2Exe is not part of the default AutoHotkey v2 install; it must be installed separately to `<install dir>\Compiler\Ahk2Exe.exe`
  (official entry point: `<install dir>\UX\install-ahk2exe.ahk`).
- Double-clicking a `.ahk` uses AutoHotkey64.exe, so when "the script works but something in the packaged exe doesn't", the very first thing to check is the artefact's bitness (the PE `machine` field must be `0x8664`).
- When debugging errors from the compiled build: a line number like `@*#1:186` in the log refers to **the script embedded in the build output**; Ahk2Exe strips comments and blank lines, so it does not line up with the `.ahk` source — re-apply the same filtering to map it.
- One behaviour difference remains between script and exe: `WinDuo.ini` lives **next to the script (or the exe)**, so copying the exe elsewhere does not take the configuration along.

## Known limitations

- Only the two equal left/right halves are supported; top/bottom halves and multi-zone layouts are out of scope (that is FancyZones' territory).
- The drag path performs exactly one move and no delayed re-check — avoiding a fight over the window 150 ms later, when you have already started the next drag.
- The drag path checks only "exclude rules / built-in popups / maximised / resize cursor"; it does not check cloak state, tool windows, or missing titles — dragging a window there yourself is proof you want it there, so no extra hurdles. Those hurdles apply only on the "automatic placement of new windows" path.
- "Follow cursor" ignores occupancy completely: the window goes to whichever side the cursor is on, even if that half is already taken — it evicts it directly.
- Program names in `[exclude]` match the **executable file name** exactly (not a substring, not a path, not a title) and **must include `.exe`**, otherwise they are not registered (log: `exclude reject: ...`).
  So every instance of the same exe, and same-named exes in different directories, get excluded together.
  Window class names work the same way, matched exactly against `GetClassNameW`; `;` is stripped as a comment, so it may appear in neither a program name nor a class name.
- Popup detection is class name + style bits, not an exhaustive catalogue: the built-in rules cover only the two most common families, `#32770` and the shell's `OperationStatusWindow`.
  For a popup that is not recognised, first look up its class with `../test/dump_windows.ahk`, then add a `class:` or `app.exe|class` line to `[exclude]`; for a fixed-size main window caught by mistake, add a `!app.exe` line.
- The UI language is read once at startup, and `EnsureExcludeSection` only appends help text "when the ini has no `[exclude]` section".
  So after switching the system language (or moving to another machine), **the Chinese/English help block that was already generated is never rewritten** — the menu and tooltip follow the new language, the ini comment does not.
  To get the help text in the new language, delete the entire `[exclude]` section and start WinDuo once more; take care not to lose your rule lines in the process.

## Repository layout

```
WinDuo.ahk        the product itself (single file, 1038 lines)
WinDuo.ini        runtime configuration (created / read / written by the script, UTF-16)
build.js          packaging: node build.js -> Release/WinDuo.exe
assets/           icon source (WinDuo.ico, used by the build)
docs/             English README (README.en.md, cross-linked with ../README.md)
```

`.gitignore` excludes: `WinDuo.ini` (per-machine configuration), `Release/` (build artefacts), `Source/` (icon drafts / generator scripts), `test/` (debug scratch — includes the measured window-feature tables and the regression scripts; not part of the product, see `../test/README.md`), plus `Thumbs.db` / `Desktop.ini`.

## License

MIT
