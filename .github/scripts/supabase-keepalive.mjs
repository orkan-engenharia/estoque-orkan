// Keeps the Supabase free-plan projects from pausing for inactivity by running one
// small read on each database. The endpoints and the public anon keys are read from
// estoque-app.html, so there is a single place to change them.
//
// Usage: node .github/scripts/supabase-keepalive.mjs [--dry-run]
import { readFileSync } from 'node:fs';

const TABLE = 'inventory';
const TIMEOUT_MS = 20000;

export function readEnvConfig(html) {
  const block = html.match(/const ENV_CONFIG = \{([\s\S]*?)\n\};/);
  if (!block) throw new Error('ENV_CONFIG not found in estoque-app.html');
  const envs = [];
  const entry = /(\w+):\s*\{\s*url:\s*'([^']+)',\s*anonKey:\s*'([^']+)'/g;
  for (const m of block[1].matchAll(entry)) envs.push({ name: m[1], url: m[2], anonKey: m[3] });
  if (!envs.length) throw new Error('no environment found in ENV_CONFIG');
  return envs;
}

async function ping(env) {
  const res = await fetch(`${env.url}/rest/v1/${TABLE}?select=id&limit=1`, {
    headers: { apikey: env.anonKey, Authorization: `Bearer ${env.anonKey}` },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const rows = await res.json();
  return Array.isArray(rows) ? rows.length : 0;
}

const isMain = process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop());
if (isMain) {
  const envs = readEnvConfig(readFileSync('estoque-app.html', 'utf8'));
  if (process.argv.includes('--dry-run')) {
    for (const env of envs) console.log(`${env.name}: ${new URL(env.url).host} (not called)`);
    process.exit(0);
  }
  let failed = 0;
  for (const env of envs) {
    try {
      const rows = await ping(env);
      console.log(`${env.name}: ok, ${rows} row(s) returned`);
    } catch (err) {
      failed += 1;
      console.error(`${env.name}: FAILED - ${err.message}`);
    }
  }
  if (failed) {
    console.error('If a project is paused, restore it in the Supabase dashboard.');
    process.exit(1);
  }
}
