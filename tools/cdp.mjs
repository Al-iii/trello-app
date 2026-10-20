import fs from 'node:fs';
import pathLib from 'node:path';

const [,, command, ...args] = process.argv;
const targets = await (await fetch('http://127.0.0.1:9223/json/list')).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith('http://127.0.0.1:53617'));
if (!target) throw new Error('Flutter page not found');

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, {once: true});
  ws.addEventListener('error', reject, {once: true});
});
let nextId = 1;
const pending = new Map();
ws.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const {resolve, reject} = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
});
function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({id, method, params}));
  return new Promise((resolve, reject) => pending.set(id, {resolve, reject}));
}
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
  return result.result.value;
}

await send('Page.enable');
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', {
  width: 390,
  height: 844,
  deviceScaleFactor: 1,
  mobile: true,
  screenWidth: 390,
  screenHeight: 844
});
await send('Emulation.setTouchEmulationEnabled', {enabled:true, maxTouchPoints:5});
await new Promise(r=>setTimeout(r,300));
if (command === 'snapshot') {
  const value = await evaluate(`(() => ({
    title: document.title,
    url: location.href,
    body: document.body.innerText,
    html: document.body.innerHTML.slice(0, 30000),
    nodes: [...document.querySelectorAll('input,button,a,[role],flt-semantics')].slice(0,500).map((e,i)=>({i,tag:e.tagName,role:e.getAttribute('role'),label:e.getAttribute('aria-label'),value:e.value||'',text:(e.innerText||e.textContent||'').trim().slice(0,200),rect:(()=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height}})()}))
  }))()`);
  console.log(JSON.stringify(value, null, 2));
} else if (command === 'eval') {
  console.log(JSON.stringify(await evaluate(args.join(' ')), null, 2));
} else if (command === 'click') {
  const [x,y] = args.map(Number);
  await send('Input.dispatchMouseEvent', {type:'mousePressed', x, y, button:'left', clickCount:1});
  await send('Input.dispatchMouseEvent', {type:'mouseReleased', x, y, button:'left', clickCount:1});
  await new Promise(r=>setTimeout(r,500));
} else if (command === 'type') {
  await send('Input.insertText', {text: args.join(' ')});
  await new Promise(r=>setTimeout(r,250));
} else if (command === 'key') {
  const key = args[0];
  const modifiers = Number(args[1] || 0);
  await send('Input.dispatchKeyEvent', {type:'keyDown', key, code:key, modifiers});
  await send('Input.dispatchKeyEvent', {type:'keyUp', key, code:key, modifiers});
  await new Promise(r=>setTimeout(r,250));
} else if (command === 'shot') {
  const path = args[0];
  const result = await send('Page.captureScreenshot', {format:'png', captureBeyondViewport:false, fromSurface:true});
  fs.mkdirSync(pathLib.dirname(path), {recursive:true});
  fs.writeFileSync(path, Buffer.from(result.data, 'base64'));
  console.log(path);
} else if (command === 'watchclick') {
  const [x,y,secondsRaw] = args.map(Number);
  const events = [];
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.method === 'Network.responseReceived') events.push({type:'response', url:message.params.response.url, status:message.params.response.status});
    if (message.method === 'Runtime.consoleAPICalled') events.push({type:'console', values:message.params.args.map(a=>a.value ?? a.description)});
    if (message.method === 'Runtime.exceptionThrown') events.push({type:'exception', text:message.params.exceptionDetails.text});
  });
  await send('Network.enable');
  await send('Input.dispatchMouseEvent', {type:'mouseMoved', x, y});
  await send('Input.dispatchMouseEvent', {type:'mousePressed', x, y, button:'left', clickCount:1});
  await send('Input.dispatchMouseEvent', {type:'mouseReleased', x, y, button:'left', clickCount:1});
  await new Promise(r=>setTimeout(r,(secondsRaw || 3)*1000));
  console.log(JSON.stringify(events, null, 2));
} else if (command === 'drag') {
  const [x1,y1,x2,y2] = args.map(Number);
  await send('Input.dispatchMouseEvent', {type:'mouseMoved', x:x1, y:y1});
  await send('Input.dispatchMouseEvent', {type:'mousePressed', x:x1, y:y1, button:'left', clickCount:1});
  await new Promise(r=>setTimeout(r,700));
  for (let i=1;i<=12;i++) {
    await send('Input.dispatchMouseEvent', {type:'mouseMoved', x:x1+(x2-x1)*i/12, y:y1+(y2-y1)*i/12, button:'left', buttons:1});
    await new Promise(r=>setTimeout(r,80));
  }
  await send('Input.dispatchMouseEvent', {type:'mouseReleased', x:x2, y:y2, button:'left', clickCount:1});
  await new Promise(r=>setTimeout(r,1500));
} else if (command === 'dragtouch') {
  const [x1,y1,x2,y2] = args.map(Number);
  await send('Input.dispatchTouchEvent', {type:'touchStart', touchPoints:[{x:x1,y:y1,id:1}]});
  await new Promise(r=>setTimeout(r,800));
  for (let i=1;i<=12;i++) {
    await send('Input.dispatchTouchEvent', {type:'touchMove', touchPoints:[{x:x1+(x2-x1)*i/12,y:y1+(y2-y1)*i/12,id:1}]});
    await new Promise(r=>setTimeout(r,80));
  }
  await send('Input.dispatchTouchEvent', {type:'touchEnd', touchPoints:[]});
  await new Promise(r=>setTimeout(r,1800));
} else if (command === 'reload') {
  await send('Page.reload', {ignoreCache:true});
  await new Promise(r=>setTimeout(r,3000));
} else if (command === 'viewport') {
  const [widthRaw, heightRaw, scaleRaw] = args.map(Number);
  await send('Emulation.setDeviceMetricsOverride', {
    width: widthRaw || 390,
    height: heightRaw || 844,
    deviceScaleFactor: scaleRaw || 1,
    mobile: true,
    screenWidth: widthRaw || 390,
    screenHeight: heightRaw || 844
  });
  await send('Emulation.setTouchEmulationEnabled', {enabled:true, maxTouchPoints:5});
  await send('Page.reload', {ignoreCache:true});
  await new Promise(r=>setTimeout(r,3500));
} else {
  throw new Error(`Unknown command: ${command}`);
}
ws.close();
