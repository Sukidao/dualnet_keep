/* 双网络守护 - WebUI 逻辑 */

const CTL = '/data/adb/modules/dualnet_keep/scripts/ctl.sh';

const $ = (id) => document.getElementById(id);
const state = {
  selected: new Set(),
  apps: [],
  icons: {},
  filter: '',
  ready: false,
};

/* ---------- 与 KernelSU 交互 ---------- */

/**
 * 兼容两种 KernelSU WebUI 实现：
 *  1) callback 风格  ksu.exec(cmd, optionsJson, callbackName) + window[callbackName](errno, stdout, stderr)
 *  2) Promise 风格   await ksu.exec(cmd, options) -> {errno, stdout, stderr}
 */
function sh(cmd, timeout = 20000) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (r) => { if (!done) { done = true; resolve(r); } };
    const timer = setTimeout(() => finish({ code: -2, out: '', err: 'timeout' }), timeout);

    if (!window.ksu || typeof ksu.exec !== 'function') {
      clearTimeout(timer);
      return finish({ code: -1, out: '', err: 'no ksu bridge' });
    }

    const cbName = `cb_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
    const cleanup = () => { clearTimeout(timer); try { delete window[cbName]; } catch {} };

    window[cbName] = (errno, stdout, stderr) => {
      cleanup();
      finish({
        code: typeof errno === 'number' ? errno : 0,
        out: stdout == null ? '' : String(stdout),
        err: stderr == null ? '' : String(stderr),
      });
    };

    let ret;
    try {
      ret = ksu.exec(cmd, '{}', cbName);
    } catch (e) {
      // 该实现可能只接受 (cmd, options)
      try { ret = ksu.exec(cmd, { cwd: '/' }); }
      catch (e2) { cleanup(); return finish({ code: -1, out: '', err: String(e2 || e) }); }
    }

    // Promise 风格：回调不会被调用，改用返回值
    if (ret && typeof ret.then === 'function') {
      ret.then((v) => {
        cleanup();
        let o = v;
        if (typeof v === 'string') {
          try { o = JSON.parse(v); } catch { o = { stdout: v }; }
        }
        o = o || {};
        finish({
          code: typeof o.errno === 'number' ? o.errno : 0,
          out: o.stdout == null ? '' : String(o.stdout),
          err: o.stderr == null ? '' : String(o.stderr),
        });
      }).catch((e) => { cleanup(); finish({ code: -1, out: '', err: String(e) }); });
    }
  });
}

/* 命令统一走绝对路径，避免 WebUI shell 的 PATH 为空 */
const SH = '/system/bin/sh';

function toast(msg, ms = 1800) {
  const el = $('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('show'), ms);
}

function kv(text) {
  const map = {};
  text.split('\n').forEach((line) => {
    const i = line.indexOf('=');
    if (i > 0) map[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  });
  return map;
}

/* ---------- 状态 ---------- */

async function loadStatus(silent) {
  try {
    const r = await sh(`${SH} ${CTL} status`);
    if (!r.out.trim()) throw new Error(r.err || `命令无输出 (code ${r.code})`);
    const s = kv(r.out);

    $('ssid').textContent = s.ssid || '未连接';
    $('ssid').className = 'value' + (s.ssid && s.ssid !== '未连接' ? ' ok' : ' dim');
    $('wifi-ip').textContent = s.wifi_ip || '无地址';

    const iface = s.mobile_iface || '';
    $('iface').textContent = iface || '未连接';
    $('iface').className = 'value' + (iface ? ' ok' : ' err');
    $('mobile-ip').textContent = s.mobile_ip || '无地址';

    $('mark').textContent = s.mark || '--';
    $('rule-count').textContent = `${s.rule_count || 0} 条跳转规则`;

    const leak = parseInt(s.wifi_leak || '0', 10);
    const leakEl = $('leak');
    leakEl.textContent = `WiFi 漏包 ${leak}`;
    leakEl.style.color = leak > 0 ? '#ff6b6b' : '';

    const alive = s.daemon === '1';
    $('daemon').textContent = alive ? '运行中' : '未运行';
    $('daemon').className = 'value ' + (alive ? 'ok' : 'err');
    $('version').textContent = s.version ? `v${s.version}` : '--';
    $('ver-foot').textContent = s.version ? `v${s.version}` : '--';

    $('keep-data').checked = s.keep_data === '1';
    $('force-route').checked = s.force_route === '1';
    $('notify').checked = s.notify === '1';
    $('app-count').textContent = s.app_count || 0;
  } catch (e) {
    if (!silent) toast(e.message || '读取状态失败');
    $('ssid').textContent = '读取失败';
    $('wifi-ip').textContent = String(e.message || e).slice(0, 40);
    $('daemon').textContent = '读取失败';
    $('daemon').className = 'value err';
  }
}

/* ---------- 应用图标 ---------- */

const ICON_KEY = 'dn_icons_v1';
const ICON_VER_KEY = 'dn_icons_ver_v1';

async function loadIcons() {
  // 1) 先用本地缓存立即渲染
  let cachedVer = null;
  try {
    cachedVer = localStorage.getItem(ICON_VER_KEY);
    const c = localStorage.getItem(ICON_KEY);
    if (c && cachedVer) {
      const obj = JSON.parse(c);
      if (obj && Object.keys(obj).length) {
        state.icons = obj;
        renderApps();
      }
    }
  } catch {}

  // 2) 问后端版本，一致就不拉数据
  try {
    const v = await sh(`${SH} ${CTL} icons-ver`, 10000);
    const ver = v.out.trim();
    if (!ver || ver === 'none') return;
    if (cachedVer && ver === cachedVer && Object.keys(state.icons).length) return;

    // 3) 版本变了才拉取完整图标数据
    const r = await sh(`${SH} ${CTL} icons`, 90000);
    if (!r.out.trim()) return;
    const obj = {};
    r.out.split('\n').forEach((line) => {
      const i = line.indexOf('|');
      if (i <= 0) return;
      obj[line.slice(0, i)] = 'data:image/webp;base64,' + line.slice(i + 1);
    });
    if (Object.keys(obj).length) {
      state.icons = obj;
      renderApps();
      try {
        localStorage.setItem(ICON_KEY, JSON.stringify(obj));
        localStorage.setItem(ICON_VER_KEY, ver);
      } catch (e) {
        // 存储空间不足时忽略，不影响本次显示
      }
    }
  } catch {}
}

/* ---------- 公网 IP ---------- */

async function loadPublicIp() {
  const w = $('wifi-pub');
  const m = $('mobile-pub');
  w.textContent = '公网 查询中…';
  m.textContent = '公网 查询中…';
  try {
    const r = await sh(`${SH} ${CTL} publicip`, 25000);
    const v = kv(r.out);
    w.textContent = '公网 ' + (v.wifi && v.wifi !== '-' ? v.wifi : '—');
    m.textContent = '公网 ' + (v.mobile && v.mobile !== '-' ? v.mobile : '—');
  } catch {
    w.textContent = '公网 —';
    m.textContent = '公网 —';
  }
}

/* ---------- 应用列表 ---------- */

function initials(item) {
  const name = item.label || item.pkg.split('.').pop() || item.pkg;
  return name.slice(0, 2);
}

function shade(pkg) {
  let h = 0;
  for (let i = 0; i < pkg.length; i++) h = (h * 31 + pkg.charCodeAt(i)) % 360;
  return `linear-gradient(135deg, hsl(${h} 72% 58%), hsl(${(h + 46) % 360} 68% 50%))`;
}

function renderApps() {
  const box = $('app-list');
  const scrollTop = box.scrollTop;
  const frag = document.createDocumentFragment();
  const kw = state.filter.trim().toLowerCase();

  // 已勾选的置顶，其余按名称排序
  const list = state.apps.slice().sort((a, b) => {
    const sa = state.selected.has(a.pkg) ? 0 : 1;
    const sb = state.selected.has(b.pkg) ? 0 : 1;
    if (sa !== sb) return sa - sb;
    return (a.label || a.pkg).localeCompare(b.label || b.pkg, 'zh-Hans-CN');
  });

  let shown = 0;
  let firstUnselected = true;
  list.forEach((item) => {
    const hit = !kw
      || item.pkg.toLowerCase().includes(kw)
      || (item.label || '').toLowerCase().includes(kw);
    if (!hit) return;
    shown++;

    const isSel = state.selected.has(item.pkg);
    if (!isSel && firstUnselected && state.selected.size > 0 && shown > 1) {
      firstUnselected = false;
      const sep = document.createElement('div');
      sep.className = 'list-sep';
      sep.textContent = '其他应用';
      frag.append(sep);
    }
    if (isSel) firstUnselected = false;

    const row = document.createElement('div');
    row.className = 'app-item' + (isSel ? ' on' : '');
    row.dataset.pkg = item.pkg;

    const av = document.createElement('div');
    av.className = 'app-avatar';
    const icon = state.icons[item.pkg];
    if (icon) {
      const img = document.createElement('img');
      img.src = icon;
      img.alt = '';
      av.append(img);
      av.style.background = 'transparent';
    } else {
      av.textContent = initials(item);
      av.style.background = shade(item.pkg);
    }

    const info = document.createElement('div');
    info.className = 'app-info';
    const nm = document.createElement('div');
    nm.className = 'app-name';
    nm.textContent = item.label || item.pkg.split('.').pop();
    const pk = document.createElement('div');
    pk.className = 'app-pkg';
    pk.textContent = item.pkg;
    info.append(nm, pk);

    const ck = document.createElement('div');
    ck.className = 'check';
    ck.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5 9.5 18 20 6.5"/></svg>';

    row.append(av, info, ck);
    frag.append(row);
  });

  box.replaceChildren(frag);
  box.scrollTop = scrollTop;
  if (!shown) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = kw ? '没有匹配的应用' : '未找到已安装应用';
    box.append(empty);
  }
  $('list-hint').textContent = `已选 ${state.selected.size} 个应用走移动数据 · 勾选后自动保存`;
}

let lastEditAt = 0;
const APPS_KEY = 'dn_apps_cache_v1';

function applyApps(out, keepSelection) {
  const sel = [];
  const inst = [];
  let section = '';
  out.split('\n').forEach((line) => {
    const t = line.trim();
    if (t === '##selected') { section = 'sel'; return; }
    if (t === '##installed') { section = 'inst'; return; }
    if (!t) return;
    if (section === 'sel') sel.push(t);
    else if (section === 'inst') {
      const [pkg, uid, label] = t.split('|');
      if (pkg) inst.push({ pkg, uid, label: label && label !== pkg ? label : '' });
    }
  });
  inst.sort((a, b) => (a.label || a.pkg).localeCompare(b.label || b.pkg, 'zh-Hans-CN'));

  if (!keepSelection) state.selected = new Set(sel);
  state.apps = inst;
  state.ready = true;
  renderApps();
  $('app-count').textContent = state.selected.size;
}

function saveAppsCache(out) {
  try { localStorage.setItem(APPS_KEY, out); } catch {}
}

async function loadApps() {
  // 1) 本地缓存，立刻显示
  let hasData = false;
  try {
    const c = localStorage.getItem(APPS_KEY);
    if (c && c.length > 20) { applyApps(c, false); hasData = true; }
  } catch {}

  // 2) 后端缓存（毫秒级）
  try {
    const r = await sh(`${SH} ${CTL} apps`, 30000);
    if (r.out.trim()) {
      applyApps(r.out, false);
      saveAppsCache(r.out);
      hasData = true;
    } else if (!hasData) {
      throw new Error(r.err || `命令无输出 (code ${r.code})`);
    }
  } catch (e) {
    if (!hasData) {
      const msg = String(e.message || e).replace(/[<>&]/g, '');
      $('app-list').innerHTML = `<div class="empty">无法读取应用列表<br><span style="font-size:11px">${msg}</span></div>`;
      toast('读取应用失败');
      return;
    }
  }

  // 3) 后台重新扫描，完成后静默更新
  refreshAppsInBackground();
}

async function refreshAppsInBackground() {
  try {
    const r0 = await sh(`${SH} ${CTL} apps-refresh`, 90000);
    if (!/^ok/.test(r0.out.trim())) return;
    const r = await sh(`${SH} ${CTL} apps`, 30000);
    if (!r.out.trim()) return;
    // 用户刚操作过勾选时，别覆盖他的选择
    applyApps(r.out, Date.now() - lastEditAt < 6000);
    saveAppsCache(r.out);
  } catch {}
}

async function syncAppsSelection() {
  try {
    const r = await sh(`${SH} ${CTL} apps`, 20000);
    if (r.out.trim()) {
      applyApps(r.out, true);
      saveAppsCache(r.out);
    }
  } catch {}
}

/* ---------- 保存 ---------- */

let saveTimer = null;
function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveApps, 600);
}

async function saveApps() {
  const text = Array.from(state.selected).sort().join('\n');
  const b64 = btoa(text);
  try {
    const r = await sh(`echo '${b64}' | base64 -d | ${SH} ${CTL} save`);
    if (!r.out.trim()) throw new Error(r.err || `保存无响应 (code ${r.code})`);
    $('app-count').textContent = state.selected.size;
    $('list-hint').textContent = `已选 ${state.selected.size} 个应用走移动数据 · 已保存`;
    const parts = r.out.trim().split(/\s+/);
    if (parts[1]) toast(`已保存 ${parts[1]} 个应用，规则已更新`);
    else toast('已保存');
    loadStatus(true);
    setTimeout(syncAppsSelection, 500);
  } catch (e) {
    toast('保存失败：' + (e.message || ''));
  }
}

/* ---------- 事件 ---------- */

function bind() {
  $('app-list').addEventListener('click', (ev) => {
    const row = ev.target.closest('.app-item');
    if (!row) return;
    const pkg = row.dataset.pkg;
    if (state.selected.has(pkg)) state.selected.delete(pkg);
    else state.selected.add(pkg);
    lastEditAt = Date.now();
    renderApps();
    $('app-count').textContent = state.selected.size;
    $('list-hint').textContent = `已选 ${state.selected.size} 个应用走移动数据 · 保存中…`;
    scheduleSave();
  });

  $('search').addEventListener('input', (ev) => {
    state.filter = ev.target.value;
    renderApps();
  });

  $('keep-data').addEventListener('change', async (ev) => {
    const v = ev.target.checked ? '1' : '0';
    await sh(`${SH} ${CTL} set keep_data ${v}`);
    toast(v === '1' ? '已开启数据链路守护' : '已关闭数据链路守护');
    loadStatus(true);
  });

  $('force-route').addEventListener('change', async (ev) => {
    const v = ev.target.checked ? '1' : '0';
    await sh(`${SH} ${CTL} set force_route ${v}`);
    toast(v === '1' ? '已开启强制分流' : '已关闭强制分流');
    loadStatus(true);
  });

  $('notify').addEventListener('change', async (ev) => {
    const v = ev.target.checked ? '1' : '0';
    await sh(`${SH} ${CTL} set notify ${v}`);
    toast(v === '1' ? '已开启状态栏通知' : '已关闭状态栏通知');
    loadStatus(true);
  });

  $('refresh').addEventListener('click', async () => {
    const btn = $('refresh');
    btn.classList.add('spin');
    await Promise.all([loadStatus(), loadApps()]);
    loadIcons();
    loadPublicIp();
    setTimeout(() => btn.classList.remove('spin'), 700);
    toast('已刷新');
  });

  $('log-toggle').addEventListener('click', async () => {
    const pre = $('log');
    const btn = $('log-toggle');
    const hidden = pre.classList.toggle('hidden');
    btn.textContent = hidden ? '展开' : '收起';
    if (!hidden) {
      const { out } = await sh(`${SH} ${CTL} log`);
      pre.textContent = out.trim() || '暂无日志';
      pre.scrollTop = pre.scrollHeight;
    }
  });
}

/* ---------- 启动 ---------- */

async function waitKsu(timeout = 3000) {
  const t0 = Date.now();
  while (!window.ksu && Date.now() - t0 < timeout) {
    await new Promise((r) => setTimeout(r, 80));
  }
  return !!window.ksu;
}

(async function boot() {
  bind();
  if (!(await waitKsu())) {
    $('app-list').innerHTML = '<div class="empty">请在 KernelSU 管理器的模块页面中打开本界面</div>';
    $('daemon').textContent = '不可用';
    return;
  }
  // 退出全屏，保留系统状态栏和导航栏
  if (typeof ksu.fullScreen === 'function') {
    try { ksu.fullScreen(false); } catch {}
  }
  await loadStatus(true);
  await loadApps();
  loadIcons();                                      // 异步加载真实图标
  loadPublicIp();                                   // 异步，不阻塞首屏
  setInterval(() => loadStatus(true), 15000);       // 自动刷新不查公网 IP，避免耗流量
})();
