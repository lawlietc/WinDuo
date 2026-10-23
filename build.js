// WinDuo 打包脚本：node build.js
// 必须显式指定 64 位基座 —— Ahk2Exe 不带 /bin 时用 32 位基座，而 32 位 user32 里没有
// GetWindowLongPtrW 导出，「新窗口自动归位」会在运行时静默失效（见 README「打包」一节）。
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const INST = process.env.AHK_DIR || 'C:\\Users\\lawli\\AppData\\Local\\Programs\\AutoHotkey';
const AKC = path.join(INST, 'Compiler', 'Ahk2Exe.exe');
const BASE = path.join(INST, 'v2', 'AutoHotkey64.exe');
const PROJ = __dirname;
const SRC = path.join(PROJ, 'WinDuo.ahk');
const ICON = path.join(PROJ, 'assets', 'WinDuo.ico');
const OUT = path.join(PROJ, 'Release', 'WinDuo.exe');
// Ahk2Exe 会强制输出文件名以 .exe 结尾（给它的名字加 .tmp 它就直接换成 .exe），
// 所以中转文件也用一个正经的 .exe 名。
const TMP = path.join(PROJ, 'Release', 'WinDuo.build.exe');

const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

for (const f of [AKC, BASE, SRC, ICON])
    if (!fs.existsSync(f)) { console.error('missing: ' + f); process.exit(1); }

// 正在运行的 exe 会锁住输出文件，Ahk2Exe 只会卡在错误对话框上，先快速失败
if (spawnSync('tasklist', ['/FI', 'IMAGENAME eq WinDuo.exe', '/NH'], { encoding: 'utf8' })
    .stdout.includes('WinDuo.exe')) {
    console.error('WinDuo.exe 正在运行，请先在托盘里退出再打包。');
    process.exit(1);
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
if (fs.existsSync(TMP)) fs.unlinkSync(TMP);

const p = spawnSync(AKC, ['/in', SRC, '/out', TMP, '/bin', BASE, '/icon', ICON, '/silent'],
    { stdio: 'inherit', windowsHide: true, timeout: 120000 });
if (p.error) { console.error('Ahk2Exe 调用失败: ' + p.error.message); process.exit(1); }

// 校验产物确实是 AMD64；Ahk2Exe 退出后文件可能还没落盘完，头几次读到的 PE 头是全 0
let machine = 0;
for (let i = 0; i < 40 && machine !== 0x8664; i++) {
    if (fs.existsSync(TMP) && fs.statSync(TMP).size > 500000) {
        const b = fs.readFileSync(TMP);
        machine = b.readUInt16LE(b.readUInt32LE(0x3C) + 4);
    } else {
        sleep(250);
    }
}
if (p.status !== 0 || machine !== 0x8664) {
    console.error('打包失败（Ahk2Exe exit=' + p.status + '，machine=0x' + machine.toString(16)
        + '）；' + OUT + ' 保持原样');
    process.exit(1);
}
fs.renameSync(TMP, OUT);
console.log('OK  ' + OUT + '  ' + fs.statSync(OUT).size.toLocaleString() + ' bytes  AMD64');
