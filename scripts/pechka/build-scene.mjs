// Собирает App/Scene/scene.html — сцену главного экрана для WKWebView.
// Источник рисунка и анимаций — scene.mjs (тот же код рисует холст Design).
// Запуск: `make scene` (нужен Node.js).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sceneSVG, sceneCSS, C } from './scene.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const svg = sceneSVG('app');
const css = sceneCSS();

// Какие слои видны в какой фазе (ключи — как у only() в scene.mjs)
const PHASES = {
  nokey: ['nokey', 'shut', 'night'],
  off: ['off', 'shut', 'night'],
  connecting: ['connecting', 'open'],
  on: ['on', 'open'],
  error: ['error', 'open'],
};
let phaseCSS = '.pk-only{display:none}';
for (const [p, keys] of Object.entries(PHASES)) {
  phaseCSS += keys.map((k) => `.ph-${p} .pk-only-${k}`).join(',') + '{display:inline}';
}

const html = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
@font-face{font-family:Marmelad;src:url(Marmelad-Regular.ttf)}
html,body{margin:0;height:100%;overflow:hidden;background:${C.log1};-webkit-user-select:none;-webkit-touch-callout:none}
.pk-scene{position:fixed;inset:0}
.pk-scene svg{width:100%;height:100%;display:block}
${phaseCSS}
${css}
</style>
</head>
<body>
<div id="scene" class="pk-scene ph-off">${svg}</div>
<script>
// Вызывается из SceneView.swift: setPhase('on') и т. п.
function setPhase(p) {
  var el = document.getElementById('scene');
  var next = 'pk-scene ph-' + p;
  if (el.className !== next) el.className = next;
}
var start = new URLSearchParams(location.search).get('phase');
if (start) setPhase(start);
</script>
</body>
</html>
`;
fs.writeFileSync(path.join(root, 'App/Scene/scene.html'), html);
console.log(`App/Scene/scene.html ${html.length} bytes`);
