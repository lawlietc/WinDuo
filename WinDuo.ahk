#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================================
;  WinDuo v2 —— 把「拖放进屏幕左半/右半」变成左右半屏吸附
;
;  相比 v1 的三处修正：
;    1. 用「光标形状」判断移动还是缩放（照抄 FancyZones 的做法），
;       不再用窗口尺寸变化判断 —— 后者会把「拖动一个已经吸附过的窗口」
;       误判成缩放，导致这类窗口永远不触发。
;    2. 摆窗口改用 SetWindowPos 直接定位，不再发 Win+方向键。
;       好处是不依赖前台窗口、不依赖「贴靠窗口」设置、也不会出现
;       「Win+左 把窗口甩到另一块显示器」的副作用。
;    3. 新窗口归位不再要求它必须是前台窗口，也不再拿「重叠面积」
;       判断它是否已占位（大窗口居中也算重叠，会误判）。
;
;  仍然保持：无低级钩子、无轮询、无绘制、不联网。
;
;  两类窗口完全不碰（拖拽不吸附、新窗口不归位、也不算它占住某一列）：
;    1. WinDuo.ini 的 [exclude] 段里手写规则命中的（程序名.exe / class:类名 / 程序名.exe|类名）
;    2. 内置识别出来的弹窗（CONFIG.popupGuard）—— 对话框、shell 文件操作进度框这类。
;       判据是「类名 + 样式位」，不能用「没有最大化按钮」这种看着更通用的样式判据：
;       复制进度框是可调大小的、有最小化按钮的，而大量固定尺寸的正常窗口没有最大化按钮。
;       实测数据见 test/README.md，弹窗用 !程序名.exe 可以放行。
;
;  新窗口的两种落位方式（托盘右键 → 放置方式 切换，选择会记在 WinDuo.ini）：
;    自动     —— 哪边空放哪边；两边都满时顶掉最近没用过的那列
;    跟随鼠标 —— 鼠标在左就放左列（或反过来的异侧模式）
; ============================================================================

CONFIG := {
    ; 判定「已经在目标半屏」的像素容差
    snapTolerance: 3,
    ; 判定「这一半已经被某个窗口占着」的像素容差（比上面宽一些，
    ; 因为窗口可能是手动拖到差不多占满半屏的）
    occupiedTolerance: 24,
    ; 光标总位移小于此值视为误触，不处理
    minDrag: 20,
    ; 松手后等系统收尾，再读窗口状态
    settleDelay: 60,
    ; 新窗口自动放到空着的那半屏
    autoPlace: true,
    ; 新窗口出现后等多久再归位（毫秒）。
    ; 这个值决定「先看到窗口在原位，然后跳过去」的那段延迟，越小越不易察觉；
    ; 太小又可能被应用自己的定位覆盖，靠下面的 verifyDelay 兜底。
    placeDelay: 40,
    ; 归位后再校验一次：有些应用在我们搬完之后才完成自己的定位，会把窗口顶回去
    verifyDelay: 150,
    ; 最多搬几次（1 = 只搬不校验）
    verifyAttempts: 2,
    ; 新窗口的落位方式：
    ;   "auto"   —— 哪边空放哪边；两边都满时顶掉最近没用过的那列
    ;   "cursor" —— 跟着鼠标走，见 cursorInvert
    placeMode: "auto",
    ; 仅 placeMode = "cursor" 时有效：
    ;   false → 鼠标在左，窗口放左列（同侧）
    ;   true  → 鼠标在左，窗口放右列（异侧）
    cursorInvert: false,
    ; 是否自动识别并排除「弹窗」：对话框、文件操作进度框这类天生不是文档窗口的小窗，
    ; 不该被拖去吸半屏，也不该算它占住某一列。判定规则见 IsPopupWindow。
    ; 想按程序放行就在 WinDuo.ini 里写 `!程序名.exe`。
    popupGuard: true,
    ; 是否把每次判定写进 %TEMP%\WinDuo.log
    debug: true
}

; ---------------------------- 界面语言 --------------------------------------
; 跟随系统 UI 语言：主语言是中文（zh-CN / zh-TW / zh-HK 的 PRIMARYLANGID 都是 0x04）出中文，
; 其余一律英文。
;
; 用 GetUserDefaultUILanguage（「设置 → 时间和语言 → 语言」里选的显示语言），
; 不用 GetUserDefaultLangID —— 那个跟的是格式区域，界面英文但区域设成中国的机器会被误判成中文。
; 只比主语言位（& 0x3F），不分地区，繁体用户同样看到中文。
IS_ZH := (DllCall("kernel32\GetUserDefaultUILanguage", "UShort") & 0x3F) = 0x04

; 面向用户的文案全在这一张表里：key -> [中文, English]。
; 加文案只往这里加 —— 在调用处硬写字符串，另一半语言必定漏翻。
;
; 日志里的判定行（start / show / end、skip:xxx、ok=1）故意不在表里：那是给人 grep 的机器词，
; 两种语言下都是同一串，test/*.js 的断言和 README 的表格都按它写。
; 只有日志里那两句纯说明的文字（reject 的提示、open-ini 的失败原因）走 T()。
TXT := Map(
    "place_auto", ["自动：空位优先，满则顶掉最久未用的那列",
        "Auto: use the free half; when both are taken, evict the least recently used column"],
    "place_same", ["跟随鼠标：鼠标在左就放左列",
        "Follow cursor: cursor on the left puts the window on the left"],
    "place_opp", ["跟随鼠标：鼠标在左就放右列",
        "Follow cursor: cursor on the left puts the window on the right"],
    "menu_place", ["放置方式", "Placement"],
    "menu_exclude", ["排除设置", "Excluded apps"],
    "menu_log", ["打开日志", "Open log"],
    "menu_exit", ["退出 WinDuo", "Exit WinDuo"],
    "tray_tip", ["WinDuo 运行中", "WinDuo is running"],
    "hook_failed", ["SetWinEventHook 失败，WinDuo 无法工作。",
        "SetWinEventHook failed - WinDuo cannot work."],
    "reject_hint", ["（程序名必须写成 xxx.exe；class:类名 这种写法除外）",
        "(program names must end with .exe; class:ClassName rules are the exception)"],
    "openini_none", ["  <-- 没打开成功：.ini 没有默认关联程序",
        "  <-- not opened: no default app is associated with .ini"],
    "openini_code", ["  <-- 没打开成功：ShellExecute 错误码 ",
        "  <-- not opened: ShellExecute error code "],
    ; [exclude] 段自动生成那段说明。逐行 `"; ` 开头、行尾 `.` 续行 ——
    ; 这是实测唯一能过 Ahk2Exe 的写法：续行里出现「空格 + 分号」会报 Missing "。
    ; 所以英文说明里要提到分号时，写成单词 semicolon，不写符号。
    "ini_help", [
        "; 一行一条规则，保存后即刻生效，不需要重启 WinDuo`r`n"
        . ";   程序名.exe          整个程序不处理（不区分大小写，.exe 必须写全）`r`n"
        . ";   class:窗口类名      任何程序里这个类的窗口都不处理`r`n"
        . ";   程序名.exe|窗口类名 只有这个程序、这个类的窗口不处理`r`n"
        . ";   !程序名.exe         豁免下面的内置弹窗判定（固定尺寸的主窗口被误伤时用）`r`n"
        . "; 行尾可以写分号注释，分号之后整段丢掉；漏了 .exe 的规则不注册，日志里打一行 exclude reject`r`n"
        . "; 弹窗（对话框、复制进度框这类）由脚本内置识别，默认就排除，不用写规则`r`n",
        "; One rule per line. Takes effect on save, no restart needed`r`n"
        . ";   app.exe             leave this program alone (case-insensitive, the .exe is required)`r`n"
        . ";   class:WndClass      leave this window class alone in every program`r`n"
        . ";   app.exe|WndClass    leave this class alone only in this program`r`n"
        . ";   !app.exe            exempt this program from the built-in popup detection below`r`n"
        . "; A semicolon mid-line starts a comment and everything after it is dropped. A rule`r`n"
        . "; without .exe is not registered; the log gets one exclude reject line instead`r`n"
        . "; Dialogs and file-operation progress boxes are detected on their own and left alone`r`n"
    ])

; 取当前语言的文案。找不到 key 直接抛：宁可启动就炸，也别让菜单显示成一个空项。
T(key) {
    global TXT, IS_ZH
    return TXT[key][IS_ZH ? 1 : 2]
}

; 托盘菜单里的三个落位方式。菜单项的名字就是这三串文案，
; 勾选/取消勾选（RefreshPlaceMenu）也拿同一个常量比，所以换语言不会错位的；
; 真正写进 ini 的是 placeMode=auto/cursor + cursorInvert=0/1，那几个标识符不翻译。
M_AUTO := T("place_auto")
M_SAME := T("place_same")
M_OPP  := T("place_opp")

; 记住上次选的落位方式，重启后沿用
if FileExist(IniPath()) {
    _m := IniRead(IniPath(), "WinDuo", "placeMode", "auto")
    _i := IniRead(IniPath(), "WinDuo", "cursorInvert", "0")
    CONFIG.placeMode := (_m = "cursor") ? "cursor" : "auto"
    CONFIG.cursorInvert := (_i = "1")
}

; ---------------------------- 常量 ------------------------------------------
EVT_MOVESIZESTART := 0x000A
EVT_MOVESIZEEND   := 0x000B
EVT_OBJECT_SHOW   := 0x8002
EVT_FOREGROUND    := 0x0003

WINEVENT_OUTOFCONTEXT   := 0x0000
WINEVENT_SKIPOWNPROCESS := 0x0002

SWP_NOZORDER   := 0x0004
SWP_NOACTIVATE := 0x0010

GWL_STYLE       := -16
GWL_EXSTYLE     := -20
WS_CAPTION      := 0x00C00000
WS_THICKFRAME   := 0x00040000
WS_EX_TOOLWINDOW := 0x00000080
WS_EX_DLGMODALFRAME := 0x00000001
WS_EX_APPWINDOW := 0x00040000
GW_OWNER        := 4
GW_CHILD        := 5
GW_HWNDNEXT     := 2

; ---------------------------- 全局状态 --------------------------------------
gMoveCb   := 0
gShowCb   := 0
gFgCb     := 0
gMoveHook := 0
gShowHook := 0
gFgHook   := 0
gPending  := 0
gBusy     := 0
; 左右两列各自最后一次被激活的时刻（GetTickCount64）。两边都占满时，
; 新窗口顶掉时间戳更小的那一列。
gSlot     := { left: 0, right: 0 }
; 排除规则，从 WinDuo.ini 的 [exclude] 段按行读，全部统一小写。
; gExcludeStamp 存 ini 的 mtime，文件被外部编辑器改过就重新读，改完即刻生效。
gExeRule  := Map()   ; exe 名            —— 整个程序不处理
gClsRule  := Map()   ; 窗口类名          —— 所有进程里该类的窗口不处理
gPairRule := Map()   ; "exe|类名"        —— 只有这个程序的这个类不处理
gNoPopup  := Map()   ; exe 名（! 前缀）  —— 豁免内置的弹窗判定
gExcludeStamp := ""
; 内置弹窗类名：这类窗口在任何程序里都是弹窗，不是文档窗口。
;   #32770                 —— Win32 标准对话框 / TaskDialog（删除确认、覆盖确认、属性页…）
;   OperationStatusWindow  —— shell 文件操作进度框（复制/移动/删除时那个）
gPopupCls := Map("#32770", 1, "operationstatuswindow", 1)
gPlaceMenu := 0

; ============================================================================
;  初始化
; ============================================================================

try DllCall("SetProcessDpiAwarenessContext", "Ptr", -4)

; 任何未捕获的运行时报错都写进日志，而不是弹一个对话框把脚本卡住
OnError(OnRuntimeError)

gMoveCb := CallbackCreate(SafeMove, "Fast")
gMoveHook := DllCall("SetWinEventHook"
    , "UInt", EVT_MOVESIZESTART
    , "UInt", EVT_MOVESIZEEND
    , "Ptr", 0
    , "Ptr", gMoveCb
    , "UInt", 0
    , "UInt", 0
    , "UInt", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    , "Ptr")

gShowCb := CallbackCreate(SafeShow, "Fast")
gShowHook := DllCall("SetWinEventHook"
    , "UInt", EVT_OBJECT_SHOW
    , "UInt", EVT_OBJECT_SHOW
    , "Ptr", 0
    , "Ptr", gShowCb
    , "UInt", 0
    , "UInt", 0
    , "UInt", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    , "Ptr")

; 记录每一列最后一次被激活的时间，用来决定两边都满时该顶掉谁
gFgCb := CallbackCreate(SafeForeground, "Fast")
gFgHook := DllCall("SetWinEventHook"
    , "UInt", EVT_FOREGROUND
    , "UInt", EVT_FOREGROUND
    , "Ptr", 0
    , "Ptr", gFgCb
    , "UInt", 0
    , "UInt", 0
    , "UInt", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
    , "Ptr")

if (!gMoveHook)
    MsgBox(T("hook_failed"), "WinDuo", 0x10)

A_TrayMenu.Delete()

gPlaceMenu := Menu()
gPlaceMenu.Add(M_AUTO, (*) => SetPlaceMode("auto"))
gPlaceMenu.Add(M_SAME, (*) => SetPlaceMode("cursor", false))
gPlaceMenu.Add(M_OPP, (*) => SetPlaceMode("cursor", true))

A_TrayMenu.Add(T("menu_place"), gPlaceMenu)
A_TrayMenu.Add(T("menu_exclude"), (*) => OpenExcludeIni())
A_TrayMenu.Add(T("menu_log"), (*) => Run(A_Temp . "\WinDuo.log"))
A_TrayMenu.Add()
A_TrayMenu.Add(T("menu_exit"), (*) => ExitApp())

RefreshPlaceMenu()
A_IconTip := T("tray_tip")

; 启动时把选中的语言写进日志：换机器/换系统语言时，这行就是「为什么界面是英文」的第一手证据
Dbg("lang=" . (IS_ZH ? "zh" : "en"))

OnExit(OnExitHandler)
Dbg("===== started =====")
Dbg("popupGuard=" . CONFIG.popupGuard)
EnsureExcludeSection()
ReloadExclude()
Dbg("exclude rules: " . ExcludeDump())

; ============================================================================
;  回调入口
;  包一层 try/catch：任何异常只写日志，不弹对话框把脚本卡死
; ============================================================================

SafeMove(hook, event, hwnd, idObject, idChild, thread, time) {
    try
        OnMoveEvent(hook, event, hwnd, idObject, idChild, thread, time)
    catch as e
        LogError("move", e)
}

SafeShow(hook, event, hwnd, idObject, idChild, thread, time) {
    try
        OnShowEvent(hook, event, hwnd, idObject, idChild, thread, time)
    catch as e
        LogError("show", e)
}

SafeForeground(hook, event, hwnd, idObject, idChild, thread, time) {
    try
        OnForeground(hook, event, hwnd, idObject, idChild, thread, time)
    catch as e
        LogError("fg", e)
}

LogError(tag, e) {
    try FileAppend(FormatTime(, "HH:mm:ss") . "  ERROR[" . tag . "]  " . e.Message
        . "   @" . e.File . ":" . e.Line . "`n", A_Temp . "\WinDuo.log")
}

; ============================================================================
;  拖动事件
; ============================================================================

OnMoveEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global gPending, gBusy, CONFIG

    if (idObject != 0 || !hwnd)
        return

    if (event = 0x000A) {                       ; EVENT_SYSTEM_MOVESIZESTART
        gPending := 0
        ReloadExclude()
        why := SkipReason(hwnd)
        if (why != "") {
            Dbg("start  skip:" . why . "      " . Desc(hwnd))
            return
        }
        if IsMaximized(hwnd) {
            Dbg("start  skip:maximized  " . Desc(hwnd))
            return
        }
        if IsResizeCursor() {
            Dbg("start  skip:resize     " . Desc(hwnd))
            return
        }
        r := GetWindowRect(hwnd)
        if !IsObject(r)
            return
        p := GetCursorPos()
        gPending := { hwnd: hwnd, w: r.r - r.l, h: r.b - r.t, cx: p.x, cy: p.y }
        Dbg("start                " . Desc(hwnd))
        return
    }

    ; ---- EVENT_SYSTEM_MOVESIZEEND ----
    if (!IsObject(gPending) || gPending.hwnd != hwnd) {
        Dbg("end    skip:no-start   " . Desc(hwnd))
        gPending := 0
        return
    }
    s := gPending
    gPending := 0

    if gBusy {
        Dbg("end    skip:busy       " . Desc(hwnd))
        return
    }
    if IsMaximized(hwnd) {
        Dbg("end    skip:maximized  " . Desc(hwnd))
        return
    }
    if (CONFIG.settleDelay > 0)
        Sleep CONFIG.settleDelay

    p := GetCursorPos()
    if (Abs(p.x - s.cx) < CONFIG.minDrag && Abs(p.y - s.cy) < CONFIG.minDrag) {
        Dbg("end    skip:too-small  dx=" . (p.x - s.cx) . " dy=" . (p.y - s.cy))
        return
    }

    hMon := MonitorFromCursor(p)
    if !hMon
        return
    wa := GetWorkArea(hMon)
    if !wa
        return

    mid := wa.l + (wa.r - wa.l) // 2
    wantLeft := (p.x < mid)
    target := HalfRect(wa, wantLeft)

    vis := GetVisibleFrame(hwnd)
    if IsSameRect(vis, target, CONFIG.snapTolerance) {
        Dbg("end    skip:already    " . Desc(hwnd))
        return
    }

    ; 拖拽这条路径只搬一次，不做延时校验：用户可能马上就又想拖动它，
    ; 150ms 后再纠正会和用户抢。
    ok := MoveWindowToRect(hwnd, target)
    Dbg("end    snap " . (wantLeft ? "L" : "R") . " ok=" . ok . " " . Desc(hwnd))
}

; ============================================================================
;  新窗口归位
; ============================================================================

OnShowEvent(hook, event, hwnd, idObject, idChild, thread, time) {
    global CONFIG
    if (!CONFIG.autoPlace || idObject != 0 || idChild != 0 || !hwnd)
        return

    ; EVENT_OBJECT_SHOW 量很大，先用「有没有标题栏」做一次极便宜的粗筛，
    ; 避免给每个菜单/控件都挂一个定时器。
    style := GetWindowLong(hwnd, GWL_STYLE)
    if !(style & WS_CAPTION)
        return

    ReloadExclude()
    why := SkipReason(hwnd)
    if (why != "") {
        Dbg("show   skip:" . why . "      " . Desc(hwnd))
        return
    }

    SetTimer(PlaceNewWindow.Bind(hwnd), -CONFIG.placeDelay)
}

PlaceNewWindow(hwnd) {
    global CONFIG, gBusy, gSlot

    if (gBusy || !WinExist("ahk_id " . hwnd))
        return
    if !DllCall("IsWindowVisible", "Ptr", hwnd) {
        Dbg("show   skip:invisible  " . Desc(hwnd))
        return
    }
    ; 再判一次：窗口刚建出来时样式可能还没定型，而且这 40ms 里名单可能被改过
    why := SkipReason(hwnd)
    if (why != "") {
        Dbg("show   skip:" . why . "      " . Desc(hwnd))
        return
    }
    if IsCloaked(hwnd) {
        Dbg("show   skip:cloaked    " . Desc(hwnd))
        return
    }
    if IsMaximized(hwnd) {
        Dbg("show   skip:maximized  " . Desc(hwnd))
        return
    }
    if IsToolWindow(hwnd) {
        Dbg("show   skip:toolwindow " . Desc(hwnd))
        return
    }
    if !HasText(hwnd) {
        Dbg("show   skip:no-text    " . Desc(hwnd))
        return
    }

    p := GetCursorPos()
    hMon := MonitorFromCursor(p)
    if !hMon
        hMon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    if !hMon
        return
    wa := GetWorkArea(hMon)
    if !wa
        return

    leftR := HalfRect(wa, true)
    rightR := HalfRect(wa, false)

    vis := GetVisibleFrame(hwnd)
    ; 用「边贴边」判断它是不是本来就吸在某一半，不能用重叠面积：
    ; 一个居中的大窗口和左半屏的重叠很容易超过 50%，会误判。
    if (IsSameRect(vis, leftR, CONFIG.snapTolerance) || IsSameRect(vis, rightR, CONFIG.snapTolerance)) {
        Dbg("show   skip:same-half  " . Desc(hwnd))
        return
    }

    ; ---- 跟随鼠标：直接按鼠标位置决定，不看占用情况 ----
    if (CONFIG.placeMode = "cursor") {
        cp := GetCursorPos()
        useLeft := (cp.x < wa.l + (wa.r - wa.l) // 2)
        if CONFIG.cursorInvert
            useLeft := !useLeft
        ok := PlaceTo(hwnd, useLeft ? leftR : rightR)
        if useLeft
            gSlot.left := TickMs()
        else
            gSlot.right := TickMs()
        Dbg("show   cursor " . (useLeft ? "L" : "R") . " ok=" . ok . " " . Desc(hwnd))
        return
    }

    ; ---- 自动：哪边空放哪边，都满时顶掉最久未用 ----
    lTaken := IsHalfOccupied(leftR, hwnd)
    rTaken := IsHalfOccupied(rightR, hwnd)

    if (lTaken && rTaken) {
        ; 两边都有人：顶掉最近没用过的那一列（时间戳更小的那个）。
        ; 两边都是 0（脚本刚启动、还没记录过）时走 else，保左列不动。
        if (gSlot.left < gSlot.right) {
            ok := PlaceTo(hwnd, leftR)
            gSlot.left := TickMs()
            Dbg("show   replace L ok=" . ok . " " . Desc(hwnd))
        } else {
            ok := PlaceTo(hwnd, rightR)
            gSlot.right := TickMs()
            Dbg("show   replace R ok=" . ok . " " . Desc(hwnd))
        }
        return
    }

    if (!lTaken) {
        ok := PlaceTo(hwnd, leftR)
        gSlot.left := TickMs()
        Dbg("show   snap L ok=" . ok . " " . Desc(hwnd))
    } else {
        ok := PlaceTo(hwnd, rightR)
        gSlot.right := TickMs()
        Dbg("show   snap R ok=" . ok . " " . Desc(hwnd))
    }
}

IsHalfOccupied(half, excludeHwnd) {
    global CONFIG

    ; 不用 EnumWindows：实测「shell 文件操作弹窗挂着一个进程在忙」时它会卡死调用方
    ; （EnumWindows 内部要做跨线程的事），而这条路径恰恰就是文件操作弹窗出现的时候。
    ; GetWindow 链是纯本地调用：桌面窗口的第一个子窗口 = 第一个顶层窗口，往后 GW_HWNDNEXT。
    h := DllCall("GetWindow", "Ptr", DllCall("GetDesktopWindow", "Ptr"), "UInt", GW_CHILD, "Ptr")
    while (h) {
        if (IsManagedWindow(h, excludeHwnd)
            && IsSameRect(GetVisibleFrame(h), half, CONFIG.occupiedTolerance)) {
            Dbg("       occupied by " . Desc(h))
            return true
        }
        h := DllCall("GetWindow", "Ptr", h, "UInt", GW_HWNDNEXT, "Ptr")
    }
    return false
}

; 这个窗口算不算「一个正常占位的窗口」。
; 桌面(Progman)、WorkerW、任务栏这些外壳窗口覆盖整屏，而 Progman 是有标题的
; （"Program Manager"），不排掉的话左右两半永远都被判成"已占用"。
; 被排除的程序和弹窗也不算占位：它们不该影响别的窗口往哪放。
IsManagedWindow(hwnd, skipHwnd) {
    if (hwnd = skipHwnd)
        return false
    if !DllCall("IsWindowVisible", "Ptr", hwnd)
        return false
    if IsToolWindow(hwnd) || IsCloaked(hwnd) || IsMaximized(hwnd)
        return false
    if !HasText(hwnd)
        return false
    if IsShellWindow(hwnd)
        return false
    return (SkipReason(hwnd) = "")
}

; ============================================================================
;  追踪每一列最后一次被用到的时刻
; ============================================================================

OnForeground(hook, event, hwnd, idObject, idChild, thread, time) {
    global gBusy
    if (gBusy || !hwnd || idObject != 0)
        return
    if IsShellWindow(hwnd) || IsToolWindow(hwnd) || IsMaximized(hwnd) || IsCloaked(hwnd)
        return
    if (SkipReason(hwnd) != "")
        return
    TouchSlotOf(hwnd)
}

; 窗口如果正贴着某一列，就把该列的时间戳刷新
TouchSlotOf(hwnd) {
    global gSlot, CONFIG
    vis := GetVisibleFrame(hwnd)
    if !IsObject(vis)
        return
    p := { x: (vis.l + vis.r) // 2, y: (vis.t + vis.b) // 2 }
    hMon := MonitorFromCursor(p)
    if !hMon
        return
    wa := GetWorkArea(hMon)
    if !wa
        return
    tick := TickMs()
    if IsSameRect(vis, HalfRect(wa, true), CONFIG.occupiedTolerance)
        gSlot.left := tick
    else if IsSameRect(vis, HalfRect(wa, false), CONFIG.occupiedTolerance)
        gSlot.right := tick
}

; 名字不能叫 Now：AHK 标识符大小写不敏感，函数 Now 会和局部变量 now 撞名，
; `now := Now()` 会被解析成「调用一个未赋值的变量」而运行时报错。
; 显式声明 Int64 返回类型，否则 32 位下返回值会被截断成 32 位。
TickMs() => DllCall("GetTickCount64", "Int64")

; ============================================================================
;  落位方式的切换与记忆
; ============================================================================

IniPath() => A_ScriptDir . "\WinDuo.ini"

SetPlaceMode(mode, invert := false) {
    global CONFIG
    CONFIG.placeMode := mode
    CONFIG.cursorInvert := invert
    try {
        IniWrite(mode, IniPath(), "WinDuo", "placeMode")
        IniWrite(invert ? 1 : 0, IniPath(), "WinDuo", "cursorInvert")
    }
    RefreshPlaceMenu()
    Dbg("mode -> " . mode . " invert=" . invert)
}

RefreshPlaceMenu() {
    global gPlaceMenu, CONFIG, M_AUTO, M_SAME, M_OPP
    if !gPlaceMenu
        return
    for name in [M_AUTO, M_SAME, M_OPP]
        gPlaceMenu.Uncheck(name)
    if (CONFIG.placeMode = "cursor")
        gPlaceMenu.Check(CONFIG.cursorInvert ? M_OPP : M_SAME)
    else
        gPlaceMenu.Check(M_AUTO)
}

; ============================================================================
;  排除规则 + 弹窗识别
;
;  规则写在 WinDuo.ini 的 [exclude] 段里，一行一条，不区分大小写。四种写法：
;
;      [exclude]
;      chrome.exe                   ; 整个程序不处理（.exe 必须写全）
;      class:OperationStatusWindow  ; 所有进程里这个类的窗口不处理
;      explorer.exe|#32770          ; 只有 explorer 的 #32770 窗口不处理
;      !Calculator.exe              ; 豁免内置弹窗判定（见 SkipReason 的 popup 分支）
;
;  行尾的 ; 注释会被剥掉（; 之后整段丢弃），所以「程序名.exe  ; 说明」这种写法是安全的；
;  少了 .exe 的规则不注册，日志里打一行 `exclude reject: <原文>`，不会悄悄失效。
;
;  为什么自己按行扫而不用 IniRead：Win32 的 ini 解析器只认 key=value，裸行会被
;  当成不存在（实测 IniRead 取回来是空串），所以这里自己读文件按行匹配。
;  写在 [exclude] 段里是为了让 IniWrite（只动 [WinDuo] 段）不会冲掉这些行；
;  扫描本身是全文件进行的，写在哪个段后面都生效。
;
;  编码注意：Win32 的 ini 解析器不认 UTF-8 BOM（带 BOM 会导致整个文件解析失败，
;  连 placeMode 都读不到），AHK IniWrite 生成的 UTF-16LE 才是安全的，
;  所以这里重写文件时固定用 UTF-16。
; ============================================================================

; ini 里还没有 [exclude] 段时补上，保证点开托盘菜单就有地方可写
EnsureExcludeSection() {
    p := IniPath()
    text := FileExist(p) ? FileRead(p) : ""
    if InStr(text, "[exclude]")
        return
    if (text = "")
        text := "[WinDuo]"
    help := T("ini_help")
    text .= "`r`n`r`n[exclude]`r`n" . help
    try {
        f := FileOpen(p, "w", "UTF-16")
        f.Write(text)
        f.Close()
    } catch as e
        LogError("exclude-init", e)
}

; ini 被外部编辑器改过（时间戳或大小变了）就重新读一遍，所以改完不用重启。
; 注意 v2 没有 FileGetMTime，取修改时间是 FileGetTime(path, "M")。
ReloadExclude() {
    global gExeRule, gClsRule, gPairRule, gNoPopup, gExcludeStamp
    p := IniPath()
    if !FileExist(p) {
        gExeRule.Clear()
        gClsRule.Clear()
        gPairRule.Clear()
        gNoPopup.Clear()
        gExcludeStamp := ""
        return
    }
    m := FileGetTime(p, "M") . "|" . FileGetSize(p)
    if (m = gExcludeStamp)
        return
    gExcludeStamp := m
    gExeRule.Clear()
    gClsRule.Clear()
    gPairRule.Clear()
    gNoPopup.Clear()
    for line in StrSplit(FileRead(p), "`n", "`r") {
        t := Trim(line)
        ; 只收裸行：注释、段头、key=value 全都跳过
        if (t = "" || SubStr(t, 1, 1) = ";" || SubStr(t, 1, 1) = "[" || InStr(t, "="))
            continue
        AddRule(t)
    }
    Dbg("exclude reloaded: " . ExcludeDump())
}

AddRule(t) {
    global gExeRule, gClsRule, gPairRule, gNoPopup

    ; 行尾的 ; 之后整段丢掉。不剥的话 `foo.exe   ; 说明` 会被当成一个叫
    ; "foo.exe   ; 说明" 的程序名存进 Map —— 规则永远命中不了，又不报错，
    ; 表现就是「名单明明写了啊」。注释单独成行也同样有效（上面 ReloadExclude 已经跳过）。
    if (cmt := InStr(t, ";"))
        t := Trim(SubStr(t, 1, cmt - 1))
    if (t = "")
        return

    if (SubStr(t, 1, 1) = "!") {
        n := Trim(SubStr(t, 2))
        if !EndsWithExe(n) {
            RejectRule(t)
            return
        }
        gNoPopup[NormExe(n)] := 1
        return
    }
    if (SubStr(t, 1, 6) = "class:") {
        k := StrLower(Trim(SubStr(t, 7)))
        if (k != "")
            gClsRule[k] := 1
        return
    }
    if (bar := InStr(t, "|")) {
        e := Trim(SubStr(t, 1, bar - 1))
        c := StrLower(Trim(SubStr(t, bar + 1)))
        if (!EndsWithExe(e) || c = "") {
            RejectRule(t)
            return
        }
        gPairRule[NormExe(e) . "|" . c] := 1
        return
    }
    if !EndsWithExe(t) {
        RejectRule(t)
        return
    }
    gExeRule[NormExe(t)] := 1
}

; 程序名一律要求写成 xxx.exe。理由：进程名是从 WinGetProcessName 拿的，本身不带扩展名，
; 省略写法全靠 NormExe 去尾对上；而去尾曾经写成 SubStr(n, -3) 拿不到 ".exe"，
; 于是「不带 .exe 的名单」整批静默失效（见 test/README.md）。要求写全之后，
; 文件里看到的名字就是进程实际的文件名，少一层“到底等不等价”的不确定性。
EndsWithExe(n) => SubStr(StrLower(Trim(n)), -4) = ".exe"

; 被拒绝的规则要在日志里点名：宁可吵一句，也别让写错的名单悄悄什么都不做。
RejectRule(t) {
    Dbg("exclude reject: " . t . "   " . T("reject_hint"))
}

ExcludeDump() {
    global gExeRule, gClsRule, gPairRule, gNoPopup
    s := ""
    for k, v in gExeRule
        s .= (s = "" ? "" : ", ") . k
    for k, v in gClsRule
        s .= (s = "" ? "" : ", ") . "class:" . k
    for k, v in gPairRule
        s .= (s = "" ? "" : ", ") . k
    for k, v in gNoPopup
        s .= (s = "" ? "" : ", ") . "!" . k
    return s
}

; 统一成「小写、去掉扩展名」，这样 Weixin.exe 和 weixin 写法都能匹配上。
; SubStr 的负数是「从倒数第 N 个字符开始」，.exe 有 4 个字符，所以取 -4：
; 写成 -3 只会拿到 "exe"，永远不等于 ".exe"，扩展名就去不掉（无 .exe 的写法因此失效）。
NormExe(name) {
    n := StrLower(Trim(name))
    if (SubStr(n, -4) = ".exe")
        n := SubStr(n, 1, -4)
    return n
}

; 最终裁决：空串 = 正常处理；非空 = 完全不碰这个窗口（拖拽不吸附、新窗口不归位、
; 也不算它占住某一列）。日志直接把原因打出来，排查时不用猜。
;
; 进程名和类名各只查一次：这条函数会被 IsHalfOccupied 对屏幕上每个窗口调用一遍，
; 拆成两个子函数各查一次就是白付一倍的 OpenProcess / GetClassName。
SkipReason(hwnd) {
    global CONFIG, gExeRule, gClsRule, gPairRule, gNoPopup, gPopupCls

    name := ProcessNameOf(hwnd)
    cls := ""
    if (gClsRule.Count || gPairRule.Count || CONFIG.popupGuard)
        cls := StrLower(ClassName(hwnd))

    ; ---- 手写规则 ----
    if (name != "" && gExeRule.Has(name))
        return "excluded"
    if (cls != "" && gClsRule.Has(cls))
        return "excluded:class"
    if (name != "" && cls != "" && gPairRule.Has(name . "|" . cls))
        return "excluded:" . name . "|" . cls

    ; ---- 内置弹窗判定：不写任何规则也该排除的那类窗口 ----
    ; 判据全部是本地 API（GetClassName / GetWindowLong / GetWindow），不跨进程发消息，
    ; 在钩子回调里调用安全。每条都是实测出来的（窗口特征表见 test/README.md）：
    ;   #32770                删除确认、覆盖确认、属性页 —— 标准对话框类
    ;   OperationStatusWindow 复制/移动进度框 —— 它可缩放、有最小化按钮、没有 owner，
    ;                         样式上和一个正常主窗口没区别，只能认类名
    ;   WS_EX_DLGMODALFRAME   带模态边框的对话框
    ;   有 owner + 不进任务栏 + 不可缩放  附属小窗，不是文档窗口
    if !CONFIG.popupGuard
        return ""
    if (name != "" && gNoPopup.Has(name))
        return ""
    if (cls != "" && gPopupCls.Has(cls))
        return "popup:" . cls
    ex := GetWindowLong(hwnd, GWL_EXSTYLE)
    if (ex & WS_EX_DLGMODALFRAME)
        return "popup:modal"
    if (DllCall("GetWindow", "Ptr", hwnd, "UInt", GW_OWNER, "Ptr")
        && !(ex & WS_EX_APPWINDOW)
        && !(GetWindowLong(hwnd, GWL_STYLE) & WS_THICKFRAME))
        return "popup:owned"
    return ""
}

; 取窗口所属进程的可执行文件名（返回的名字本身不带 .exe）。WinGetProcessName 走的是
; GetWindowThreadProcessId + 进程查询 API，不跨进程发消息，在钩子回调里调用安全。
; 取不到就返回空串按「不排除」处理：宁可多管一次，也别因为名单写错就整体失效。
ProcessNameOf(hwnd) {
    try
        return NormExe(WinGetProcessName(hwnd))
    return ""
}

; 用「系统默认的关联程序」打开配置文件：ShellExecuteW 的 open 动词，不指定任何程序。
; 返回值是 HINSTANCE，>32 才是成功；<=32 是 SE_ERR_* 错误码（2=文件不存在，31=没有关联程序），
; 打不开时把路径和错误码一起写进日志，免得只能靠猜。
OpenExcludeIni() {
    EnsureExcludeSection()
    ReloadExclude()
    p := IniPath()
    r := DllCall("shell32\ShellExecuteW", "Ptr", 0, "WStr", "open", "WStr", p,
        "Ptr", 0, "Ptr", 0, "Int", 1, "Ptr")
    Dbg("open-ini " . p . " ret=" . r
        . (r > 32 ? "" : (r = 31 ? T("openini_none") : T("openini_code") . r)))
}

; ============================================================================
;  摆放窗口
; ============================================================================

HalfRect(wa, left) {
    mid := wa.l + (wa.r - wa.l) // 2
    if left
        return { l: wa.l, t: wa.t, r: mid, b: wa.b }
    return { l: mid, t: wa.t, r: wa.r, b: wa.b }
}

; 搬一次，然后隔 verifyDelay 再看一眼。有些应用在我们搬完之后才完成
; 自己的定位（还原上次尺寸、等渲染完成再调整），会把窗口顶回去；
; 这里补一次纠正，但仍然只纠正「已经漂走」的情况，不跟用户抢。
PlaceTo(hwnd, target, attempt := 1) {
    global CONFIG, gPending

    if !WinExist("ahk_id " . hwnd)
        return false

    ; 用户正在手动拖动这个窗口，别跟他抢
    if (attempt > 1 && IsObject(gPending))
        return true

    if (attempt > 1 && IsSameRect(GetVisibleFrame(hwnd), target, CONFIG.snapTolerance))
        return true

    ok := MoveWindowToRect(hwnd, target)
    if (attempt < CONFIG.verifyAttempts)
        SetTimer(PlaceTo.Bind(hwnd, target, attempt + 1), -CONFIG.verifyDelay)
    return ok
}

; 目标矩形是「可见外框」。SetWindowPos 要的是窗口矩形，两者差一圈不可见边框，
; 用两边的差值把它补回去，摆完屏幕上的可见边缘才正好落在半屏上。
MoveWindowToRect(hwnd, target) {
    global CONFIG, gBusy

    vis := GetVisibleFrame(hwnd)
    wr := GetWindowRect(hwnd)
    if (!IsObject(vis) || !IsObject(wr))
        return false

    dl := vis.l - wr.l
    dt := vis.t - wr.t
    dr := vis.r - wr.r
    db := vis.b - wr.b

    ; 可见外框 = 窗口矩形 + (dl, dt) 到 (dr, db) 的差值。
    ; 反过来求窗口矩形：
    ;   vis.l = x + dl              → x = target.l - dl
    ;   vis.r = x + w + dr          → w = targetW + dl - dr
    ; 之前把 w/h 的符号写反了，窗口会被摆窄 2*(dl-dr) 像素，
    ; 左右各露出一条 8px 的缝——就是看起来的「边距」。
    x := target.l - dl
    y := target.t - dt
    w := (target.r - target.l) + dl - dr
    h := (target.b - target.t) + dt - db
    if (w <= 0 || h <= 0)
        return false

    gBusy := 1
    try {
        ; hWndInsertAfter = 0 即 HWND_TOP：把窗口提到 z 序最上层，
        ; 这样顶掉某一列时新窗口不会被原来的窗口盖住。
        ; 带 SWP_NOACTIVATE，不抢焦点。
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0
            , "Int", x, "Int", y, "Int", w, "Int", h
            , "UInt", SWP_NOACTIVATE)
    } finally {
        gBusy := 0
    }
    return true
}

; ============================================================================
;  Win32 小工具
; ============================================================================

GetCursorPos() {
    buf := Buffer(8, 0)
    if !DllCall("GetCursorPos", "Ptr", buf)
        return { x: 0, y: 0 }
    return { x: NumGet(buf, 0, "Int"), y: NumGet(buf, 4, "Int") }
}

; 光标是不是缩放手柄。移动和缩放在 WinEvent 里长得一模一样，
; 只能靠这个区分（FancyZones 也是这么做的）。
IsResizeCursor() {
    ci := Buffer(24, 0)
    NumPut("UInt", 24, ci, 0)                  ; cbSize
    if !DllCall("GetCursorInfo", "Ptr", ci)
        return false
    hCur := NumGet(ci, 8, "Ptr")
    if !hCur
        return false
    for id in [32644, 32645, 32642, 32643] {   ; SIZEWE, SIZENS, SIZENWSE, SIZENESW
        if (hCur = DllCall("LoadCursorW", "Ptr", 0, "Ptr", id, "Ptr"))
            return true
    }
    return false
}

; POINT 是按值传递的 8 字节结构，x 在低 32 位、y 在高 32 位
MonitorFromCursor(pt) {
    packed := (pt.y << 32) | (pt.x & 0xFFFFFFFF)
    return DllCall("MonitorFromPoint", "Int64", packed, "UInt", 2, "Ptr")
}

GetWorkArea(hMon) {
    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi, 0)                  ; cbSize
    if !DllCall("GetMonitorInfoW", "Ptr", hMon, "Ptr", mi)
        return 0
    return {
        l: NumGet(mi, 20, "Int"),
        t: NumGet(mi, 24, "Int"),
        r: NumGet(mi, 28, "Int"),
        b: NumGet(mi, 32, "Int")
    }
}

GetWindowRect(hwnd) {
    buf := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", buf)
        return 0
    return { l: NumGet(buf, 0, "Int"), t: NumGet(buf, 4, "Int"), r: NumGet(buf, 8, "Int"), b: NumGet(buf, 12, "Int") }
}

GetVisibleFrame(hwnd) {
    buf := Buffer(16, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", buf, "UInt", 16, "Int")
    if (hr != 0)
        return GetWindowRect(hwnd)
    return { l: NumGet(buf, 0, "Int"), t: NumGet(buf, 4, "Int"), r: NumGet(buf, 8, "Int"), b: NumGet(buf, 12, "Int") }
}

IsSameRect(a, b, tol) {
    if (!IsObject(a) || !IsObject(b))
        return false
    return (Abs(a.l - b.l) <= tol && Abs(a.t - b.t) <= tol && Abs(a.r - b.r) <= tol && Abs(a.b - b.b) <= tol)
}

IsMaximized(hwnd) => DllCall("IsZoomed", "Ptr", hwnd) ? true : false

IsCloaked(hwnd) {
    v := 0
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &v, "UInt", 4, "Int")
    return (hr = 0 && v != 0)
}

IsToolWindow(hwnd) {
    ex := GetWindowLong(hwnd, GWL_EXSTYLE)
    return (ex & WS_EX_TOOLWINDOW) ? true : false
}

; GetWindowLongPtrW 只在 64 位 user32 里真实存在（64 位下它是个宏），
; 32 位进程 DllCall 它会抛 "Call to nonexistent function"。按指针宽度选导出名，
; 脚本在 32/64 位解释器和 32/64 位编译产物里行为一致。
GetWindowLong(hwnd, index) {
    if (A_PtrSize = 8)
        return DllCall("GetWindowLongPtrW", "Ptr", hwnd, "Int", index, "Ptr")
    return DllCall("GetWindowLongW", "Ptr", hwnd, "Int", index, "UInt")
}

; ============================================================================
;  日志
; ============================================================================

; 只用类名，不用 WinGetTitle：标题要走消息发给别的进程，
; 对方卡住时会把我们的钩子回调一起拖住。
ClassName(hwnd) {
    buf := Buffer(512, 0)
    DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", buf, "Int", 256)
    return StrGet(buf, , "UTF-16")
}

Desc(hwnd) => hwnd . " [" . ClassName(hwnd) . "]"

; 桌面、壁纸宿主、任务栏这些外壳窗口
IsShellWindow(hwnd) {
    if (hwnd = DllCall("GetShellWindow", "Ptr"))
        return true
    cls := ClassName(hwnd)
    return (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
}

; 判断窗口有没有标题，用直接 API，不发消息
HasText(hwnd) => DllCall("GetWindowTextLengthW", "Ptr", hwnd, "Int") > 0

Dbg(msg) {
    global CONFIG
    if !CONFIG.debug
        return
    try FileAppend(FormatTime(, "HH:mm:ss") . "  " . msg . "`n", A_Temp . "\WinDuo.log")
}

; 未捕获错误的兜底：写日志，不弹窗，继续运行
OnRuntimeError(err, mode) {
    LogError("global", err)
    return true
}

OnExitHandler(*) {
    global gMoveHook, gShowHook, gFgHook
    if gMoveHook
        DllCall("UnhookWinEvent", "Ptr", gMoveHook)
    if gShowHook
        DllCall("UnhookWinEvent", "Ptr", gShowHook)
    if gFgHook
        DllCall("UnhookWinEvent", "Ptr", gFgHook)
}
