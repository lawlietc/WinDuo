# WinDuo

**简体中文** | [English](docs/README.en.md)

<p align="center">
  把「拖进屏幕左半 / 右半」变成左右半屏吸附的 Windows 轻量工具。
</p>

WinDuo 是一个单文件 [AutoHotkey v2](https://www.autohotkey.com/) 脚本：拖动窗口到屏幕任意一侧松手，窗口即吸附为该侧半屏；新出现的窗口还能按你选择的策略自动放到空着的一半。不联网、无轮询、无低级键盘/鼠标钩子、不在屏幕上绘制任何东西。

## 功能

- **拖拽吸附** —— 把窗口拖到工作区左半边或右半边，松手即贴合该半屏（用 `SetWindowPos` 直接定位，不模拟 Win+方向键，因此不受"贴靠窗口"设置影响，也不会把窗口甩到其他显示器）。
- **新窗口自动归位** —— 新打开的窗口自动放到空着的那半屏，两种策略（托盘右键随时切换，选择会记忆）：
  - **自动**：哪边空放哪边；两边都满时，顶掉最近没用过的那一列（哪列"最近没用过"由 `EVENT_FOREGROUND` 维护的两列时间戳决定）。
  - **跟随鼠标**：鼠标在左放左列（同侧），或反过来的异侧模式；这条路径直接按鼠标位置决定，不看占用情况。
  - 归位只针对「看起来是个文档窗口」的窗口：有标题栏样式、有标题文本、没被 DWM cloak（不在其他虚拟桌面）、
    不是工具窗、没最大化、而且当前没吸在任何一半上 —— 任一条不满足就跳过，日志里写明是哪一条（`skip:cloaked` 等）。
- **多显示器感知** —— 按光标所在显示器的工作区计算半屏，正确处理任务栏 / 左右停靠的工具条。
- **界面语言跟随系统** —— 托盘菜单、悬停提示、错误框、以及 `WinDuo.ini` 里自动生成的 `[exclude]`
  说明，中文系统出中文，其余一律英文（判定细节见「界面语言」一节）。
- **排除程序** —— 名单里写的 exe 完全交给系统自己管：拖拽不吸附、新窗口不自动归位、也不算它占住某一列（配置见下）。
- **排除弹窗（默认开启，无需配置）** —— 对话框、复制/删除进度框这类「天生不是文档窗口」的小窗自动被认出来并跳过，
  否则资源管理器弹个「确认删除」就会被甩到半屏上，界面很怪。判据见「弹窗识别」一节，可用 `!程序名.exe` 放行。
- **移动 vs 缩放区分** —— 靠光标形状判断（与 FancyZones 同款做法），拖动已吸附过的窗口不会被误判成缩放。
- **DWM 可见外框对齐** —— 用 `DwmGetWindowAttribute` 拿可见边框而非窗口矩形，摆完后屏幕上正好严丝合缝占满半屏，不会露出不可见阴影边。
- **不跟用户抢** —— 你正在手动拖动窗口时，自动归位的延时校验会主动让位。

## 系统要求

- Windows 10 / 11
- [AutoHotkey v2](https://www.autohotkey.com/download/)（v2.0 及以上；脚本首行 `#Requires AutoHotkey v2.0`）
- 跑打包好的 `Release\WinDuo.exe` 不需要装 AutoHotkey（解释器基座已经内嵌在 exe 里）

## 快速开始

1. 安装 AutoHotkey v2。
2. 双击 `WinDuo.ahk` 运行（或 `node build.js` 出 `Release\WinDuo.exe` 后双击它）。
3. 托盘出现图标（悬停显示 "WinDuo 运行中"），右键可：
   - **放置方式** —— 三个子菜单项，当前生效的一项打勾：
     `自动：空位优先，满则顶掉最久未用的那列` / `跟随鼠标：鼠标在左就放左列` / `跟随鼠标：鼠标在左就放右列`；
     选择写入 `WinDuo.ini` 的 `[WinDuo]` 段（`placeMode` / `cursorInvert`），重启后沿用；
   - **排除设置** —— 用系统默认的关联程序打开 `WinDuo.ini`（不指定编辑器），改完保存即刻生效；
     点开时日志里会多一行 `open-ini <路径> ret=<n>`，`ret` 大于 32 才算真拉起了程序，
     小于等于 32 是 `SE_ERR_*`（2 = 文件不存在，31 = `.ini` 没有关联程序）——
     点了没反应先看这行，别靠猜；
   - **打开日志** —— 查看 `%TEMP%\WinDuo.log`；
   - **退出 WinDuo**。

开机自启：`Win+R` 输入 `shell:startup`，把 `WinDuo.ahk`（或 `WinDuo.exe`）的快捷方式放进去即可。
重复启动会直接替换掉旧实例（`#SingleInstance Force`），不会出现两个 WinDuo 抢同一个窗口。

### 界面语言

认的是 **系统 UI 语言**（`GetUserDefaultUILanguage` 的主语言位）：`0x04`（zh-CN / zh-TW / zh-HK 共用这个
主语言码）显示中文，其它语言一律英文。不看地区格式 —— 用 `GetUserDefaultLangID` 会把「界面是英文、
但区域格式设成中国」的机器误判成中文，所以用的是 UI 语言那个。

- 翻译的范围：托盘四个菜单项 + 三个放置方式子项、托盘悬停提示、`SetWinEventHook` 失败那个错误框、
  `EnsureExcludeSection` 往 ini 里补的那段 `[exclude]` 说明，以及日志里两句纯说明的文字
  （`exclude reject` 的提示、`open-ini` 的失败原因）。
- 不翻译的：日志里的判定行（`start` / `show` / `end`、`skip:excluded`、`snap L ok=1` 这些）和 ini 里
  的标识符（`placeMode` / `cursorInvert` / `[exclude]` / `class:`）。前者是给人 grep 的机器词，
  `test/*.js` 的断言按它写；后者是配置键，翻译了就没法解析了。
- 文案集中在脚本顶部一张表 `TXT := Map(key -> [中文, English])`，取文案只走 `T(key)`。
  加新文案往表里加，在调用处硬写字符串必定漏掉另一半语言。
- 启动那行日志 `lang=zh` / `lang=en` 就是「这次为什么是这个语言」的证据。
- 验证：`node test/lang_check.js` —— 把 `IS_ZH` 钉成 true / false 各跑一趟，断言两套文案
  （英文那趟顺带断言全程没有汉字），最后一趟不改脚本，验本机确实选中了正确的一套。

## 使用方式

| 操作 | 结果 |
|------|------|
| 拖动窗口，松手时光标在左半屏 | 窗口吸附为左半屏 |
| 拖动窗口，松手时光标在右半屏 | 窗口吸附为右半屏 |
| 打开新窗口 | 按托盘选定的放置方式自动落位 |
| 拖动最大化的窗口 | 不处理（避免与系统拖出还原行为打架） |
| 光标呈缩放手柄时的拖动 | 不处理（这是缩放，不是移动） |
| 拖动 / 打开 `[exclude]` 里列出的程序 | 不处理，完全交给系统 |
| 打开对话框 / 文件操作进度框（默认） | 不吸附、不归位、不算占位 |
| 打开没标题栏 / 没标题文本 / 工具窗 / 被其他虚拟桌面 cloak 的窗口 | 不归位，也不算占位 |
| 打开本来就吸在某一半的窗口 | 不重复搬运 |
| 松手时窗口已经正好等于目标半屏 | 不动它（日志 `skip:already`） |

## 配置

大部分行为参数集中在脚本顶部的 `CONFIG` 对象里（改这些要重启脚本才生效 —— 只有 `[exclude]` 段是热加载的）：

| 键 | 默认值 | 说明 |
|----|--------|------|
| `snapTolerance` | `3` | 判定"已经在目标半屏"的像素容差 |
| `occupiedTolerance` | `24` | 判定"该半屏已被占用"的像素容差 |
| `minDrag` | `20` | 光标位移小于此值视为误触，不处理 |
| `settleDelay` | `60` | 松手后等系统收尾的毫秒数 |
| `autoPlace` | `true` | 是否启用新窗口自动归位 |
| `placeDelay` | `40` | 新窗口出现后延迟多久归位 |
| `verifyDelay` | `150` | 归位后再次校验的延迟（部分应用会自己把窗口顶回去） |
| `verifyAttempts` | `2` | 最多搬运次数，`1` = 只搬不校验 |
| `placeMode` | `"auto"` | 落位方式：`auto` / `cursor`（托盘菜单会改写它） |
| `cursorInvert` | `false` | 仅 `cursor` 模式有效：同侧 `false` / 异侧 `true`（托盘菜单会改写它） |
| `popupGuard` | `true` | 是否自动识别并排除弹窗（见「弹窗识别」） |
| `debug` | `true` | 是否把判定过程写入 `%TEMP%\WinDuo.log` |

持久化的配置都在脚本同目录的 `WinDuo.ini` 里（UTF-16 编码，由脚本自己创建 / 读写）。下面就是脚本自己生成的
样子——`[exclude]` 段不存在时脚本会补上那段说明注释，保证点开就有地方可写，最后四行才是用户加的规则：

```ini
[WinDuo]
placeMode=cursor
cursorInvert=1

[exclude]
; 一行一条规则，保存后即刻生效，不需要重启 WinDuo
;   程序名.exe          整个程序不处理（不区分大小写，.exe 必须写全）
;   class:窗口类名      任何程序里这个类的窗口都不处理
;   程序名.exe|窗口类名 只有这个程序、这个类的窗口不处理
;   !程序名.exe         豁免下面的内置弹窗判定（固定尺寸的主窗口被误伤时用）
; 行尾可以写分号注释，分号之后整段丢掉；漏了 .exe 的规则不注册，日志里打一行 exclude reject
; 弹窗（对话框、复制进度框这类）由脚本内置识别，默认就排除，不用写规则
foobar2000.exe
class:OperationStatusWindow
explorer.exe|#32770
!Calculator.exe
```

`[exclude]` 段的四种写法（都是裸行，没有 key）：

| 写法 | 含义 |
|------|------|
| `程序名.exe` | 按**进程的可执行文件名**匹配，忽略大小写、比上去掉 `.exe`；规则里 `.exe` 必须写全 |
| `class:窗口类名` | 匹配窗口类名（`GetClassNameW`），不分进程，不带 `.exe` |
| `程序名.exe\|窗口类名` | 两个条件同时命中才排除，用来处理「同一个类名在不同程序里意思不一样」 |
| `!程序名.exe` | 只豁免**内置弹窗判定**，手写规则仍然生效 |

命中任一规则后：拖拽不吸附、新窗口不自动归位，也不参与「哪一半被占住了」的判断——它不该影响别的窗口往哪放。

- 保存即刻生效，不用重启（脚本按文件的时间戳 + 大小判断有没有被改过）。
- 行尾的 `;` 之后整段丢掉，所以 `foobar2000.exe   ; 音乐播放器` 是安全写法；注释单独占一行也一样有效。
  代价是**程序名 / 窗口类名里不能出现 `;`**（`;` 本来就是 Windows 文件名非法字符，只有极少数自定义窗口类会踩到）。
- 省略 `.exe` 的规则**不注册**，日志里打一行 `exclude reject: <原文>` —— 宁可吵一句，也别让写错的名单悄悄什么都不做。
  历史上省写法靠 `NormExe` 去掉扩展名去对 `WinGetProcessName` 的返回值，而去掉那一步曾经写错（`SubStr(n, -3)`），
  整批不带 `.exe` 的名单静默失效；现在要求写全，文件里看到的名字就是进程实际的文件名。
- 写完看日志里的 `exclude reloaded: <规则>` 一行，那才是脚本真正注册下去的东西。
- 含 `=` 的行会被当成 `key=value` 直接跳过（所以规则里不能出现 `=`）；以 `[` 开头的行被当成段头跳过。
- 扫描是**全文件**进行的，规则写在哪个段之后都生效；放进 `[exclude]` 只是为了不被 `IniWrite`（只动 `[WinDuo]` 段）冲掉。
- 别用 UTF-8 保存这个文件：Win32 的 ini 解析器遇到 UTF-8 BOM 会整个文件解析失败（连 `placeMode` 都读不到），
  而 `IniWrite` / 脚本自己重写时固定用 UTF-16，所以「记事本打开→改→保存为 ANSI/UTF-8」这条路径是会坏的，
  用系统默认的 UTF-16 保存，或者干脆只往 `[exclude]` 段里加行。
- `[exclude]` 段是给脚本自己按行扫的，`IniRead` 读不到裸行（Win32 ini 只认 `key=value`），所以别指望
  用 ini 的 API 去读它。

### 弹窗识别

不用写任何规则，下面这几类窗口默认就被排除 —— 因为「在文件夹里删个文件，确认框被甩到半屏」这种体验
不该要求用户先学会配置：

| 判据 | 抓到的东西 |
|------|-----------|
| 窗口类名 `#32770` | 标准对话框 / TaskDialog：删除确认、覆盖确认、属性页、另存为… |
| 窗口类名 `OperationStatusWindow` | shell 文件操作进度框（复制 / 移动 / 删除时那个） |
| `WS_EX_DLGMODALFRAME` 样式位 | 带模态边框的对话框（顺带抓到了 toast，`#32768`） |
| 有 owner + 不进任务栏 + 不可缩放 | 框架自己画的附属小弹窗 |

前两条必须**认类名**，样式上没有出路（实测数据在 `test/README.md`）：

- 复制进度框 `OperationStatusWindow` 是**可缩放的、有最小化按钮、没有 owner** 的，样式和一个正常主窗口
  完全没区别。看着最顺手的判据「没有最大化按钮就别管」会把这类窗口一起误伤 —— AHK 的 `Gui()`、
  大量固定尺寸的工具窗口都没有最大化按钮。
- 反过来，删除 / 覆盖确认框的样式特征（`WS_POPUP` + 无最小最大按钮 + 模态边框）非常显著，
  但类名判定已经覆盖它了，不必再依赖样式。

误伤了自己的主窗口时（少数把主窗口做成 `#32770` 的老程序），在 `[exclude]` 里写一行 `!程序名.exe` 放行。
日志里每条判定都带原因，不用猜。

## 排查

日志写在 `%TEMP%\WinDuo.log`（`CONFIG.debug` 关掉就不写），托盘「打开日志」直接看。每行一个动作 + 一个原因，
窗口只用 `hwnd [类名]` 标识（不打标题，原因见「实现要点」）。

| 前缀 | 出现在哪 | 含义 |
|------|---------|------|
| `start skip:excluded` / `excluded:class` / `excluded:程序名\|类名` | 按下拖动起点 | 命中 `[exclude]` 手写规则 |
| `start skip:popup:#32770` / `popup:operationstatuswindow` / `popup:modal` / `popup:owned` | 按下拖动起点 | 内置弹窗判定命中（四类判据各对应一条） |
| `start skip:maximized` | 按下拖动起点 | 窗口处于最大化态 |
| `start skip:resize` | 按下拖动起点 | 光标是缩放手柄，这是缩放不是移动 |
| `end skip:too-small dx=.. dy=..` | 松手 | 位移没到 `minDrag`，当误触丢掉 |
| `end skip:busy` | 松手 | 自动归位正在搬别的窗口，让位 |
| `end skip:already` | 松手 | 已经贴合目标半屏（在 `snapTolerance` 内），不动 |
| `end skip:no-start` | 松手 | 只收到 END 没收到 START（起点就被各种 skip 拦掉了） |
| `end snap L/R ok=1` | 松手 | 拖拽吸附完成 |
| `show skip:invisible/cloaked/maximized/toolwindow/no-text/same-half` | 新窗口出现 | 该窗口不算文档窗口，或本来就吸在某一半 |
| `show snap L/R ok=` / `show cursor L/R ok=` / `show replace L/R ok=` | 新窗口归位 | 三种落位结果：填空位 / 跟随鼠标 / 顶掉一列 |
| `       occupied by hwnd [类名]` | 扫描占位 | 判定某一半已被谁占住，直接看出"为什么没往这边放" |
| `exclude reloaded: <规则>` | 任意事件 | `[exclude]` 被外部编辑器改过，已重新加载（列出的才是真正生效的名单） |
| `exclude reject: <原文>` | 加载 `[exclude]` | 这条规则被拒绝（程序名漏了 `.exe`）—— 写错名单唯一会留下的痕迹 |
| `mode -> cursor invert=1` | 托盘切换 | 落位方式改动并已写入 ini |
| `open-ini <路径> ret=<n>` | 托盘「排除设置」 | `ret<=32` 是没拉起来（2 = 文件不存在，31 = `.ini` 没关联程序） |
| `ERROR[move/show/fg/global] ...` | 回调外层 | 异常被 `try/catch` 吞掉只记日志，脚本继续跑 |

没有标题栏样式的窗口在 `OBJECT_SHOW` 的粗筛里就被丢掉了，连一行日志都不会打（那个事件量太大，先过滤再挂定时器）。
日志是纯追加、不轮转，长了直接删文件即可，脚本会在下一次写入时重新创建。日志用系统 ANSI 码页写（`FileAppend` 的默认行为），
记事本看没问题，但规则里写了中文注释时用 UTF-8 编辑器打开会是一堆乱码 —— 那乱码不是脚本读错了 ini，是看日志的工具错了。

编译版（exe）里的报错行号是**编译产物内嵌脚本**的行号，和 `.ahk` 源码对不上 —— Ahk2Exe 会剥掉注释和空行，
要按同样规则过滤一遍再映射。

## 实现要点

- 全部事件来自 `SetWinEventHook`（`MOVESIZESTART/END`、`OBJECT_SHOW`、`FOREGROUND`），out-of-context，
  无轮询、无全局钩子；三个 hook 都带 `WINEVENT_SKIPOWNPROCESS`，WinDuo 自己的窗口不会触发回调。
- 挂 hook 之前先 `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)`：半屏矩形是按 `GetMonitorInfoW` 返回的
  工作区像素直接算的，进程不声明 DPI 感知的话系统会对我们的坐标做虚拟化，非 100% 缩放下算出来的半屏边界和实际
  对不上，两半之间会留缝、或者甩到相邻显示器上。
- `OBJECT_SHOW` 事件量很大，先用"有没有标题栏样式"做极便宜的粗筛，再挂一次性定时器。
- 判断半屏是否被占用用"边贴边"而不是重叠面积——居中的大窗口与某一半重叠很容易超过 50%，会误判。
- 两边都满时顶掉哪一列，靠 `EVENT_FOREGROUND` 维护的两个时间戳（左右列各自最后一次被激活的 `GetTickCount64`），
  时间戳更小的那列被顶掉；两个都是 0（脚本刚启动）时保左列不动。
- 遍历顶层窗口用 `GetWindow(GW_CHILD / GW_HWNDNEXT)` 而不是 `EnumWindows`：实测有 shell 文件操作
  弹窗挂着时 `EnumWindows` 会把调用方卡死（它内部要做跨线程的事），而「新窗口归位」这条路径
  恰恰就是文件操作弹窗出现的时候。
- 判定用的 API 以本地调用为主（`GetClassNameW` / `GetWindowLong` / `GetWindow` / `WinGetProcessName`），
  刻意不去取标题全文——那要跨进程发 `WM_GETTEXT`，对方卡住会把我们的钩子回调一起拖住。
  新窗口路径上判断"有没有标题"用 `GetWindowTextLengthW`：跨进程时它同样会发 `WM_GETTEXTLENGTH`，
  但只取回一个整数、不搬字符串，被拖住的风险比取全文小一个量级，换掉「无标题的边框窗口也去归位」这类误伤。
- 摆窗口用 `SetWindowPos`，`hWndInsertAfter = HWND_TOP` + `SWP_NOACTIVATE`：顶掉某一列时新窗口不会被原窗口盖住，
  同时不抢焦点。搬完的矩形是「可见外框」，所以先用 `DwmGetWindowAttribute` 拿到不可见边框的差值再补回去。
- 排除 `Progman` / `WorkerW` / 任务栏等外壳窗口，否则它们覆盖整屏，两半永远被判定为"已占用"。
- 日志只记录窗口类名不记录标题：原因同上条。
- 任何未捕获异常都写入日志而不是弹窗卡死脚本（`OnError` + 每个回调外层 `try/catch`）。
- 改脚本时的解析坑：表达式**续行**（以 `.` 开头那种）里的字符串，只要出现「空格 + `;`」就直接报
  `Missing "` —— `"; 行尾可以写 ; 注释"` 实测炸，改成全角 `；` 或让 `;` 紧跟引号就正常。
  `EnsureExcludeSection` 生成给 `[exclude]` 的那段说明正踩在这条线上，别把 ASCII 分号塞回那个字符串里。
- 语法校验用编译做（Ahk2Exe 通过 = 0，失败 = 17 并在 stderr 打 `Missing "`/行号），`AutoHotkey64.exe /validate`
  在这台机器上会挂住不返回，不能当 gate；`test/compile.js` 就是拿编译当语法检查器用的。

## 与同类工具对比

|  | WinDuo | Windows 自带 Snap |
| :---- | :---- | :---- |
| 体积 | 单文件脚本，约 39 KB / 1038 行 | 系统内置 |
| 拖到半屏即吸附 | ✅ | 需拖到顶部/侧边缘触发 |
| 新窗口自动归位 | ✅ | ❌ |
| 按 exe 名排除程序 | ✅ | ❌（只能整体关掉贴靠） |
| 按窗口类名排除 / 默认排除弹窗 | ✅ | ❌（确认框照样被贴靠） |
| 不依赖"贴靠窗口"设置 | ✅ | — |
| 无绘制 / 无联网 | ✅ | ✅ |

## 打包成 exe

用仓库里的 `build.js`（`node build.js`），它做的事是：

```
Ahk2Exe /in WinDuo.ahk /out Release\WinDuo.build.exe /bin <安装目录>\v2\AutoHotkey64.exe /icon assets\WinDuo.ico /silent
```

AutoHotkey 的安装目录默认取 `%LOCALAPPDATA%\Programs\AutoHotkey`，装在别处用环境变量 `AHK_DIR` 覆盖。
脚本还会：`WinDuo.exe` 正在运行时直接报错退出（不然 Ahk2Exe 会卡在弹框里）、先编到
`Release\WinDuo.build.exe` 校验通过再改名覆盖成 `Release\WinDuo.exe`（编坏时不会把上一次能用的产物删掉）、
以及读 PE 头确认 `machine == 0x8664`（Ahk2Exe 退出后文件可能还没落盘完，头几次读到的 PE 头是全 0，所以要带延时重试）。
产物约 1.24 MB（基座 + 内嵌脚本 + 图标）。

- **`/bin` 必须显式指向 `AutoHotkey64.exe`。** 不给这个参数时 Ahk2Exe 会用 32 位基座，而
  `SetWinEventHook` 的回调里要读窗口样式：`GetWindowLongPtrW` 这个导出**只存在于 64 位的
  user32**（在 C/C++ 头文件里它是个宏，`DllCall` 是运行时按名字找导出，找不到就抛
  `Call to nonexistent function.`）。异常被回调外层的 `try/catch` 吞掉只写日志，于是表现成
  「拖拽吸附正常、新窗口自动归位静默失效」。（脚本里已改成按 `A_PtrSize` 选
  `GetWindowLongPtrW` / `GetWindowLongW`，两种位数都能跑；但打包仍然固定出 64 位产物。）
- 只需要出**一个**包：64 位。64 位 Windows 上 WOW64 能跑 32 位程序，但反过来不行，而WinDuo
  的目标机器都是 64 位，出两个包只会让「下错包」变成一种 bug 来源。
- Ahk2Exe 不在 AutoHotkey v2 的默认安装里，需要单独装到 `<安装目录>\Compiler\Ahk2Exe.exe`
  （官方入口：`<安装目录>\UX\install-ahk2exe.ahk`）。
- 双击 `.ahk` 走的是 AutoHotkey64.exe，所以「脚本正常、打包后某个功能失效」这种反差，
  第一件事就查产物的位数（PE `machine` 字段应为 `0x8664`）。
- 排查编译版报错时注意：日志里 `@*#1:186` 的行号是**编译产物内嵌脚本**的行号，Ahk2Exe 会剥掉
  注释和空行，和 `.ahk` 源码行号对不上，要按同样的规则过滤一遍再映射。
- 脚本 / exe 的行为差异只剩一处：`WinDuo.ini` 放在**脚本（或 exe）所在目录**，所以把 exe 拷到
  别的目录去跑，配置不会跟着走。

## 已知限制

- 仅支持左右两等分半屏；上/下半屏与多分区布局不在设计范围内（那属于 FancyZones 的领域）。
- 拖拽路径只做一次搬运、不做延时校验——避免 150ms 后与你刚发起的下一次拖动抢窗口。
- 拖拽路径只查「排除规则 / 内置弹窗 / 最大化 / 缩放光标」，不查 cloak、工具窗、无标题——你把窗口手动拖过去
  就说明你要它在那儿，不该再多设门槛。那几项门槛只在「新窗口自动归位」这条路径上生效。
- 「跟随鼠标」模式完全不看占用情况：鼠标在哪边就放哪边，哪怕那一半已经有人了，直接顶掉它。
- `[exclude]` 里的程序名按**可执行文件名**精确匹配（不是子串、不是路径、不是标题），且**必须写全 `.exe`**，
  漏了就不注册（日志 `exclude reject: ...`）。所以同一个 exe 的所有实例、以及不同目录下同名的 exe，会一起被排除。
  窗口类名同理，按 `GetClassNameW` 的结果精确匹配；`;` 会被当注释剥掉，所以程序名和类名里都不能出现它。
- 弹窗识别认的是类名 + 样式位，不是穷举：内置只覆盖 `#32770` 和 shell 的 `OperationStatusWindow`
  这两类最常见的。遇到没被认出来的弹窗，先用 `test/dump_windows.ahk` 看它的类名，再往 `[exclude]`
  里加一行 `class:` 或 `程序名.exe|类名`；遇到被误伤的固定尺寸主窗口，加一行 `!程序名.exe`。
- 界面语言只在启动时取一次，且 `EnsureExcludeSection` 是「ini 里没有 `[exclude]` 段才补说明」。
  所以换系统语言（或换了台机器）之后，**已经生成过的那段中文/英文说明不会被改写** —— 菜单和提示会跟着变，
  ini 里那段注释不会。想要新语言的说明，把 `[exclude]` 段整段删掉再重开一次即可，规则行自己留意别一起丢了。

## 仓库结构

```
WinDuo.ahk        产品本体（单文件，1038 行）
WinDuo.ini        运行时配置（脚本自己创建 / 读写，UTF-16）
build.js          打包：node build.js -> Release/WinDuo.exe
assets/           图标源（WinDuo.ico，打包用）
docs/             英文版 README（README.en.md，与本文档互为语言跳转）
```

`.gitignore` 里忽略了：`WinDuo.ini`（每台机器自己的配置）、`Release/`（打包产物）、`Source/`（图标草稿 /
生成脚本）、`test/`（调试杂物，含实测窗口特征表和回归脚本，不是产品的一部分，见 `test/README.md`）、
以及 `Thumbs.db` / `Desktop.ini`。

## License

MIT
