/// Ye page dusre device ke browser mein khulta hai (PC ya mobile, koi app install nahi).
/// Isse files upload (bhejna) aur download (lena) dono ho jaate hain.
const String kWebPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SwiftFiles Transfer</title>
<style>
:root{--sky:#4DB6F5;--dark:#1E88E5;--soft:#E3F2FD;--bg:#F4F9FF;--ink:#1B2B3A;--muted:#7A8CA0}
*{box-sizing:border-box}
body{margin:0;font-family:system-ui,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--ink)}
header{background:linear-gradient(135deg,#6CC4F8,#1E88E5);color:#fff;padding:30px 20px 44px;border-radius:0 0 28px 28px}
header h1{margin:0;font-size:24px}
header p{margin:6px 0 0;opacity:.9;font-size:14px}
main{max-width:680px;margin:-26px auto 40px;padding:0 16px}
.card{background:#fff;border-radius:22px;padding:20px;margin-bottom:16px;box-shadow:0 8px 24px rgba(30,136,229,.10)}
h2{margin:0 0 12px;font-size:17px}
input[type=password],input[type=text],input[type=tel]{width:100%;padding:14px 16px;font-size:20px;letter-spacing:6px;text-align:center;border:2px solid var(--soft);border-radius:14px;outline:none;background:var(--bg)}
input:focus{border-color:var(--sky)}
button,.btn{display:inline-block;width:100%;margin-top:12px;padding:14px;border:0;border-radius:14px;background:var(--dark);color:#fff;font-size:16px;font-weight:700;cursor:pointer;text-align:center}
.err{color:#EF5350;margin:10px 0 0;min-height:20px;text-align:center}
.drop{border:2px dashed var(--sky);background:var(--soft);border-radius:18px;padding:30px 16px;text-align:center;color:var(--dark);font-weight:600}
.drop.over{background:#cfe9fd}
.row{display:flex;justify-content:space-between;gap:12px;padding:13px 14px;margin-bottom:8px;border-radius:14px;background:var(--bg);color:var(--ink);text-decoration:none}
.row span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:600}
.row small{color:var(--muted);white-space:nowrap}
.row:hover{background:var(--soft)}
.muted{color:var(--muted);text-align:center}
.up{margin-top:10px;font-size:14px}
.up span{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bar{height:8px;border-radius:8px;background:var(--soft);margin-top:4px;overflow:hidden}
.bar i{display:block;height:100%;width:0;background:var(--sky);transition:width .15s}
.up.ok .bar i{background:#26A69A}
.up.bad .bar i{background:#EF5350}
[hidden]{display:none!important}
</style>
</head>
<body>
<header>
  <h1>SwiftFiles Transfer</h1>
  <p>Bina cable ke files bhejein aur lein</p>
</header>
<main>
  <section class="card" id="lock">
    <h2>PIN daalein</h2>
    <input id="pin" type="tel" inputmode="numeric" maxlength="4" placeholder="----" autocomplete="off">
    <button onclick="unlock()">Connect</button>
    <div class="err" id="err"></div>
  </section>

  <div id="app" hidden>
    <section class="card">
      <h2>Files bhejein</h2>
      <label class="drop" id="drop">
        Yahan files drop karein ya tap karke chunein
        <input id="pick" type="file" multiple hidden>
      </label>
      <div id="queue"></div>
    </section>
    <section class="card">
      <h2>Download karein</h2>
      <div id="files"></div>
    </section>
  </div>
</main>

<script>
let pin = sessionStorage.getItem('pin') || '';
const $ = id => document.getElementById(id);

function fmt(n){
  if (n < 1024) return n + ' B';
  const u = ['KB','MB','GB']; let i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < 2);
  return n.toFixed(n >= 10 ? 0 : 1) + ' ' + u[i];
}

async function load(){
  try {
    const r = await fetch('/api/files', {headers: {'x-pin': pin}});
    if (!r.ok) return false;
    render(await r.json());
    return true;
  } catch (e) { return false; }
}

function render(files){
  const box = $('files');
  box.textContent = '';
  if (!files.length) {
    const p = document.createElement('p');
    p.className = 'muted';
    p.textContent = 'Abhi koi file nahi hai.';
    box.appendChild(p);
    return;
  }
  files.forEach(f => {
    const a = document.createElement('a');
    a.className = 'row';
    a.href = '/download?name=' + encodeURIComponent(f.name) + '&pin=' + encodeURIComponent(pin);
    const n = document.createElement('span'); n.textContent = f.name;
    const s = document.createElement('small'); s.textContent = fmt(f.size);
    a.append(n, s);
    box.appendChild(a);
  });
}

async function unlock(){
  pin = $('pin').value.trim();
  if (await load()) {
    sessionStorage.setItem('pin', pin);
    $('lock').hidden = true;
    $('app').hidden = false;
    setInterval(load, 5000);
  } else {
    $('err').textContent = 'PIN galat hai ya server band hai';
  }
}

function upload(file){
  return new Promise(done => {
    const row = document.createElement('div');
    row.className = 'up';
    const name = document.createElement('span');
    name.textContent = file.name;
    const bar = document.createElement('div'); bar.className = 'bar';
    const fill = document.createElement('i'); bar.appendChild(fill);
    row.append(name, bar);
    $('queue').prepend(row);

    const x = new XMLHttpRequest();
    x.open('PUT', '/upload?name=' + encodeURIComponent(file.name));
    x.setRequestHeader('x-pin', pin);
    x.upload.onprogress = e => { if (e.lengthComputable) fill.style.width = (e.loaded / e.total * 100) + '%'; };
    x.onload = () => { fill.style.width = '100%'; row.classList.add(x.status === 200 ? 'ok' : 'bad'); done(); };
    x.onerror = () => { row.classList.add('bad'); done(); };
    x.send(file);
  });
}

async function sendAll(list){
  for (const f of Array.from(list)) await upload(f);
  load();
}

$('pick').addEventListener('change', e => sendAll(e.target.files));
const drop = $('drop');
['dragover','dragenter'].forEach(t => drop.addEventListener(t, e => { e.preventDefault(); drop.classList.add('over'); }));
['dragleave','drop'].forEach(t => drop.addEventListener(t, e => { e.preventDefault(); drop.classList.remove('over'); }));
drop.addEventListener('drop', e => sendAll(e.dataTransfer.files));
$('pin').addEventListener('keydown', e => { if (e.key === 'Enter') unlock(); });

if (pin) { $('pin').value = pin; unlock(); }
</script>
</body>
</html>
''';
