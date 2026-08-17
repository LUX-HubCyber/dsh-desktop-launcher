'use strict'

/**
 * DeepSeek Harness 桌面端（Electron 主进程）。
 *
 * 职责：
 *  1. 定位 deepseek-harness 源码目录与 node 可执行文件（可配置）。
 *  2. 若 127.0.0.1:3080 已有健康服务，则直接复用；否则拉起
 *     `node --import tsx/esm apps/cli/src/bin.ts web`（等价于 pnpm dsh web）。
 *  3. 轮询等待服务就绪后，用内置窗口打开 Harness Web 界面。
 *  4. 退出时优雅停止由本应用拉起的服务进程。
 */

const { app, BrowserWindow, dialog, Menu, shell } = require('electron')
const { spawn } = require('node:child_process')
const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')

const APP_NAME = 'DeepSeek Harness'
const DEFAULT_HOST = '127.0.0.1'
const DEFAULT_PORT = 3080
// 默认 harnessPath 为「目录名」形式（deepseek-harness），
// 前面的盘符/上级目录会在不同电脑上自动搜索解析。
const DEFAULT_HARNESS = 'deepseek-harness'
const READY_TIMEOUT_MS = 120_000
const GRACEFUL_KILL_MS = 3_000

let mainWindow = null
let splashWindow = null
let serverProcess = null
let serverOwned = false
let serverError = null
let quitting = false
let currentUrl = ''

// 固定用户数据目录（settings.json 所在处），避免 productName 含空格导致路径不一致。
app.setPath('userData', path.join(app.getPath('appData'), 'dsh-desktop'))


// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

function settingsFilePath() {
  return path.join(app.getPath('userData'), 'settings.json')
}

function defaultSettings() {
  return {
    harnessPath: DEFAULT_HARNESS,
    nodePath: '',
    host: DEFAULT_HOST,
    port: DEFAULT_PORT,
  }
}

function loadSettings() {
  const merged = defaultSettings()
  try {
    const fromFile = JSON.parse(fs.readFileSync(settingsFilePath(), 'utf8'))
    Object.assign(merged, fromFile)
  } catch {
    /* 首次运行或配置损坏时使用默认值 */
  }
  if (process.env.DSH_HARNESS_PATH) merged.harnessPath = process.env.DSH_HARNESS_PATH
  if (process.env.DSH_DESKTOP_PORT && /^\d+$/.test(process.env.DSH_DESKTOP_PORT)) {
    merged.port = Number(process.env.DSH_DESKTOP_PORT)
  }
  if (process.env.DSH_DESKTOP_HOST) merged.host = process.env.DSH_DESKTOP_HOST
  return merged
}

function ensureSettingsFile() {
  const p = settingsFilePath()
  if (!fs.existsSync(p)) {
    try {
      fs.mkdirSync(path.dirname(p), { recursive: true })
      fs.writeFileSync(p, JSON.stringify(defaultSettings(), null, 2) + '\n')
    } catch {
      /* 忽略写入失败（例如只读环境） */
    }
  }
}

// ---------------------------------------------------------------------------
// 路径解析
// ---------------------------------------------------------------------------

function isValidHarnessDir(dir) {
  if (!dir) return false
  return (
    fs.existsSync(path.join(dir, 'apps', 'cli', 'src', 'bin.ts')) &&
    fs.existsSync(path.join(dir, 'node_modules'))
  )
}

/** 把配置里的路径规整为「尾路径」：去掉开头/结尾的 \ 或 /。 */
function normalizeHarnessSuffix(configured) {
  return String(configured || '').trim().replace(/^[\\/]+/, '').replace(/[\\/]+$/, '')
}

/** 生成用于搜索 harness 的候选基目录（去重，含各级祖先与各磁盘根目录）。 */
function candidateBaseDirs() {
  const bases = []
  const addWithAncestors = (start) => {
    if (!start) return
    let dir = path.resolve(start)
    while (true) {
      if (!bases.includes(dir)) bases.push(dir)
      const parent = path.dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  }

  // 便携版 exe 所在目录（electron-builder 便携包运行时会设置该环境变量）
  addWithAncestors(process.env.PORTABLE_EXECUTABLE_DIR)
  // 实际可执行文件所在目录
  addWithAncestors(path.dirname(process.execPath))
  // 应用自身路径（开发模式：项目目录）
  addWithAncestors(app.getAppPath())
  // 当前工作目录
  addWithAncestors(process.cwd())
  // 用户主目录
  addWithAncestors(os.homedir())
  // 各磁盘根目录
  for (let code = 65; code <= 90; code++) {
    const drive = `${String.fromCharCode(code)}:\\`
    if (fs.existsSync(drive)) bases.push(drive)
  }
  return bases
}

function resolveHarnessPath(settings) {
  const configured = String(settings.harnessPath || '').trim()

  // 1) 直接命中：绝对路径或相对路径本身即有效
  if (isValidHarnessDir(configured)) return path.resolve(configured)

  // 2) 作为「尾路径」搜索：<候选基目录>\<尾路径>
  const suffix = normalizeHarnessSuffix(configured)
  if (suffix) {
    for (const base of candidateBaseDirs()) {
      const candidate = path.resolve(base, suffix)
      if (isValidHarnessDir(candidate)) return candidate
    }
  }

  return null
}

function resolveNodeExecutable(settings) {
  if (settings.nodePath && fs.existsSync(settings.nodePath)) return settings.nodePath
  const candidates = [
    'C:\\Program Files\\nodejs\\node.exe',
    'C:\\Program Files (x86)\\nodejs\\node.exe',
    path.join(os.homedir(), 'scoop', 'apps', 'nodejs', 'current', 'node.exe'),
  ]
  for (const c of candidates) {
    if (fs.existsSync(c)) return c
  }
  return 'node'
}

// ---------------------------------------------------------------------------
// HTTP 探测
// ---------------------------------------------------------------------------

function probeUrl(url, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false
    const done = (result) => {
      if (!settled) {
        settled = true
        resolve(result)
      }
    }
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      res.resume()
      done({ ok: true, statusCode: res.statusCode })
    })
    req.on('timeout', () => {
      req.destroy()
      done({ ok: false, code: 'TIMEOUT' })
    })
    req.on('error', (err) => done({ ok: false, code: err.code }))
  })
}

async function isHealthy(url) {
  const r = await probeUrl(url, 2500)
  return r.ok && typeof r.statusCode === 'number'
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function waitForServer(url, timeoutMs, onProgress) {
  const startedAt = Date.now()
  let lastState = '连接被拒绝'
  while (Date.now() - startedAt < timeoutMs) {
    if (serverError) {
      throw new Error(`启动 Harness 服务失败：${serverError.message}（请确认已安装 Node.js 且 node 在 PATH 中）`)
    }
    const r = await probeUrl(url, 2500)
    if (r.ok && r.statusCode < 500) return
    lastState = r.ok ? `HTTP ${r.statusCode}` : (r.code || '未知错误')
    if (onProgress) onProgress(`等待服务就绪…（${lastState}）`)
    await sleep(600)
  }
  throw new Error(`服务在 ${Math.round(timeoutMs / 1000)} 秒内未就绪（最后状态：${lastState}）`)
}

// ---------------------------------------------------------------------------
// 服务进程
// ---------------------------------------------------------------------------

function startServerProcess(settings, harnessPath) {
  const nodeExecutable = resolveNodeExecutable(settings)
  const args = ['--import', 'tsx/esm', 'apps/cli/src/bin.ts', 'web']
  if (settings.port !== DEFAULT_PORT) args.push('--port', String(settings.port))

  const child = spawn(nodeExecutable, args, {
    cwd: harnessPath,
    env: { ...process.env },
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  })

  let outputTail = ''
  const collect = (chunk) => {
    const text = String(chunk)
    outputTail = (outputTail + text).slice(-4000)
    // 服务打印的 URL 行也是就绪信号之一，转发到启动日志
    process.stdout.write(text)
  }
  child.stdout.on('data', collect)
  child.stderr.on('data', collect)

  child.on('error', (err) => {
    serverError = err
    if (quitting) return
    const win = mainWindow && !mainWindow.isDestroyed() ? mainWindow : null
    if (win) {
      dialog.showErrorBox(APP_NAME, `启动 Harness 服务失败：${err.message}\n\n请确认已安装 Node.js 且 node 在 PATH 中。`)
      win.close()
    }
  })

  child.on('exit', (code, signal) => {
    serverProcess = null
    if (quitting) return
    if (serverOwned && mainWindow && !mainWindow.isDestroyed()) {
      dialog.showErrorBox(
        APP_NAME,
        `Harness 服务已退出（code=${code ?? ''}${signal ? ` signal=${signal}` : ''}）。\n\n${outputTail}`,
      )
      mainWindow.close()
    }
  })

  return child
}

function stopOwnedServer() {
  if (!serverOwned || !serverProcess) return
  const child = serverProcess
  serverProcess = null
  try {
    // Windows 下 SIGINT 尽可能触发优雅关闭；随后兜底强杀。
    child.kill('SIGINT')
  } catch {
    /* 进程可能已退出 */
  }
  setTimeout(() => {
    try {
      if (child.exitCode === null) child.kill('SIGKILL')
    } catch {
      /* 忽略 */
    }
  }, GRACEFUL_KILL_MS)
}

// ---------------------------------------------------------------------------
// 窗口
// ---------------------------------------------------------------------------

function splashHtmlContent(status, logo) {
  return [
    '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">',
    '<style>',
    'html,body{margin:0;height:100%;font-family:"Segoe UI","Microsoft YaHei",sans-serif;',
    'background:#11141a;color:#e6e8ee;display:flex;align-items:center;justify-content:center;',
    'user-select:none;}',
    '.card{text-align:center;padding:30px 40px;width:100%;box-sizing:border-box;}',
    '.logo{width:64px;height:64px;border-radius:16px;margin:0 auto 16px;overflow:hidden;}',
    'h1{font-size:17px;margin:0 0 4px;font-weight:600;}',
    '#status{font-size:13px;color:#9aa3b2;margin:0 0 20px;min-height:18px;}',
    '.steps{display:flex;justify-content:center;gap:16px;margin-bottom:20px;}',
    '.step{display:flex;align-items:center;gap:5px;font-size:11px;color:#565e6c;}',
    '.step .dot{width:7px;height:7px;border-radius:50%;background:#2a2f3a;display:inline-block;flex:none;}',
    '.step.done{color:#9aa3b2;}',
    '.step.done .dot{background:#4d6bfe;}',
    '.step.active{color:#e6e8ee;}',
    '.step.active .dot{background:#4d6bfe;box-shadow:0 0 0 3px rgba(77,107,254,.22);}',
    '.spinner{width:20px;height:20px;margin:0 auto;border:3px solid rgba(77,107,254,.25);',
    'border-top-color:#4d6bfe;border-radius:50%;animation:spin .8s linear infinite;}',
    '@keyframes spin{to{transform:rotate(360deg)}}',
    '</style></head><body><div class="card">',
    `<div class="logo">${logo ? `<img src="${logo}" style="width:100%;height:100%;display:block;"/>` : 'DSH'}</div>`,
    '<h1>DeepSeek Harness</h1>',
    `<p id="status">${status}</p>`,
    '<div class="steps">',
    '<div class="step" id="s1"><span class="dot"></span>初始化</div>',
    '<div class="step" id="s2"><span class="dot"></span>定位</div>',
    '<div class="step" id="s3"><span class="dot"></span>启动服务</div>',
    '<div class="step" id="s4"><span class="dot"></span>打开界面</div>',
    '</div>',
    '<div class="spinner"></div>',
    '</div></body></html>',
  ].join('')
}

/** 读取运行时图标（assets/icon.png）作为加载弹窗 Logo。 */
function readSplashLogo() {
  try {
    const buf = fs.readFileSync(path.join(__dirname, '..', 'assets', 'icon.png'))
    return 'data:image/png;base64,' + buf.toString('base64')
  } catch {
    return null
  }
}

function createSplash() {
  const logo = readSplashLogo()
  const win = new BrowserWindow({
    width: 440,
    height: 320,
    frame: false,
    resizable: false,
    transparent: false,
    backgroundColor: '#11141a',
    alwaysOnTop: true,
    center: true,
    show: true,
    icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true },
  })
  win.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(splashHtmlContent('正在初始化…', logo)))
  return win
}

function updateSplash(text, step) {
  if (!splashWindow || splashWindow.isDestroyed()) return
  const safe = JSON.stringify(text)
  let js = `document.getElementById('status').textContent = ${safe};`
  if (step && step >= 1 && step <= 4) {
    js += `
      for (let i = 1; i <= 4; i++) {
        const el = document.getElementById('s' + i);
        el.classList.toggle('done', i < ${step});
        el.classList.toggle('active', i === ${step});
      }`
  }
  splashWindow.webContents.executeJavaScript(js).catch(() => {})
}

// 关闭启动弹窗；保证弹窗至少显示 MIN_SPLASH_MS 毫秒，避免启动太快时用户看不到进度。
function closeSplashSoon(startedAt) {
  const MIN_SPLASH_MS = 900
  const close = () => {
    if (splashWindow && !splashWindow.isDestroyed()) splashWindow.close()
    splashWindow = null
  }
  const elapsed = Date.now() - (startedAt || 0)
  setTimeout(close, Math.max(0, MIN_SPLASH_MS - elapsed))
}

function isInternalUrl(url) {
  return (
    url.startsWith('http://127.0.0.1') ||
    url.startsWith('http://localhost') ||
    url.startsWith('http://[::1]')
  )
}

/** 窗口标题：应用名 + 版本号。 */
function appTitle() {
  return 'DeepSeek Harness Desktop'//`DeepSeek Harness Desktop v${app.getVersion()}`
}

function createMainWindow(url) {
  const win = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    title: appTitle(),
    backgroundColor: '#0f1115',
    show: false,
    icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  })

  win.once('ready-to-show', () => {
    win.show()
    win.focus()
    win.moveTop()
  })

  // 固定标题：页面加载后会用自己的 <title> 覆盖窗口标题，这里强制回应用名+版本号。
  win.on('page-title-updated', (event) => {
    event.preventDefault()
    win.setTitle(appTitle())
  })

  win.webContents.setWindowOpenHandler(({ url: target }) => {
    if (isInternalUrl(target)) return { action: 'allow' }
    shell.openExternal(target)
    return { action: 'deny' }
  })

  win.webContents.on('will-navigate', (event, target) => {
    if (isInternalUrl(target)) return
    event.preventDefault()
    shell.openExternal(target)
  })

  win.on('closed', () => {
    if (mainWindow === win) mainWindow = null
  })

  win.loadURL(url)
  return win
}

// ---------------------------------------------------------------------------
// 菜单
// ---------------------------------------------------------------------------

function buildMenu() {
  const template = [
    {
      label: '文件',
      submenu: [
        { label: '在浏览器中打开', click: () => { if (currentUrl) shell.openExternal(currentUrl) } },
        { type: 'separator' },
        { label: '退出', accelerator: 'Ctrl+Q', click: () => app.quit() },
      ],
    },
    {
      label: '视图',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: '帮助',
      submenu: [
        {
          label: '打开配置文件',
          click: () => {
            ensureSettingsFile()
            shell.openPath(settingsFilePath())
          },
        },
        {
          label: '关于',
          click: () => {
            dialog.showMessageBox({
              title: '关于',
              message: APP_NAME,
              detail:
                `DeepSeek Harness 桌面端\n版本 ${app.getVersion()}\n\n` +
                '自动启动 Harness Web 服务并打开界面，免去手动执行 pnpm dsh web 与输入网址。',
            })
          },
        },
      ],
    },
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

// ---------------------------------------------------------------------------
// 启动流程
// ---------------------------------------------------------------------------

async function boot() {
  const settings = loadSettings()
  ensureSettingsFile()

  const splashStartedAt = Date.now()
  splashWindow = createSplash()
  updateSplash('正在初始化…', 1)

  const harnessPath = resolveHarnessPath(settings)
  if (!harnessPath) {
    throw new Error(
      '未找到 DeepSeek Harness 源码目录（需要 apps/cli/src/bin.ts 与 node_modules）。\n\n' +
        `请在配置文件 ${settingsFilePath()} 中设置 harnessPath 为正确路径，\n` +
        '或设置环境变量 DSH_HARNESS_PATH。',
    )
  }

  updateSplash('正在定位 DeepSeek Harness…', 2)

  const url = `http://${settings.host}:${settings.port}`
  currentUrl = url

  if (await isHealthy(url)) {
    updateSplash('检测到已运行的服务，直接连接…', 3)
    serverOwned = false
  } else {
    updateSplash('正在启动 Harness 服务…', 3)
    serverProcess = startServerProcess(settings, harnessPath)
    serverOwned = true
    await waitForServer(url, READY_TIMEOUT_MS, updateSplash)
    updateSplash('服务已就绪，正在打开界面…', 4)
  }

  mainWindow = createMainWindow(url)
  closeSplashSoon(splashStartedAt)
}

function failStartup(err) {
  if (splashWindow && !splashWindow.isDestroyed()) splashWindow.close()
  splashWindow = null
  stopOwnedServer()
  dialog.showErrorBox(
    APP_NAME,
    `启动失败\n\n${err && err.message ? err.message : String(err)}`,
  )
  app.exit(1)
}

// ---------------------------------------------------------------------------
// 应用生命周期
// ---------------------------------------------------------------------------

const gotLock = app.requestSingleInstanceLock()
if (!gotLock) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })

  app.whenReady().then(() => {
    buildMenu()
    boot().catch(failStartup)
  })

  app.on('before-quit', () => {
    quitting = true
    stopOwnedServer()
  })

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit()
  })
}
