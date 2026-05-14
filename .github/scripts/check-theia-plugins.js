#!/usr/bin/env node
/**
 * Checks Open VSX Registry for newer versions of plugins declared
 * in package.json's `theiaPlugins` and updates them in place.
 */

const fs = require('fs');
const path = require('path');

const PACKAGE_FILE = path.join(process.cwd(), 'package.json');
const pkg = JSON.parse(fs.readFileSync(PACKAGE_FILE, 'utf8'));

if (!pkg.theiaPlugins) {
  console.log('No theiaPlugins section found.');
  process.exit(0);
}

// Extract the publisher, extension name and version from an Open VSX URL.
// Example: https://open-vsx.org/api/redhat/vscode-yaml/1.15.0/file/redhat.vscode-yaml-1.15.0.vsix
function parseUrl(url) {
  const match = url.match(
    /open-vsx\.org\/api\/([^/]+)\/([^/]+)\/([^/]+)\/file\//
  );
  if (!match) return null;
  return {
    publisher: match[1],
    name: match[2],
    version: match[3],
  };
}

async function getLatestVersion(publisher, name) {
  const url = `https://open-vsx.org/api/${publisher}/${name}/latest`;
  const res = await fetch(url, {
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) {
    console.warn(`  Failed to fetch ${publisher}/${name}: HTTP ${res.status}`);
    return null;
  }
  const data = await res.json();
  return {
    version: data.version,
    downloadUrl: data.files && data.files.download,
  };
}

function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

(async () => {
  const changes = [];
  let updated = false;

  for (const [key, url] of Object.entries(pkg.theiaPlugins)) {
    const parsed = parseUrl(url);
    if (!parsed) {
      console.log(`Skipping ${key}: URL format not recognized.`);
      continue;
    }

    console.log(`Checking ${parsed.publisher}/${parsed.name}...`);
    const latest = await getLatestVersion(parsed.publisher, parsed.name);
    if (!latest || !latest.downloadUrl) {
      console.log(`  No version info available.`);
      continue;
    }

    if (compareVersions(latest.version, parsed.version) > 0) {
      console.log(`  Update: ${parsed.version} -> ${latest.version}`);
      pkg.theiaPlugins[key] = latest.downloadUrl;
      changes.push(
        `- \`${key}\`: ${parsed.version} → **${latest.version}**`
      );
      updated = true;
    } else {
      console.log(`  Up to date (${parsed.version}).`);
    }
  }

  if (updated) {
    fs.writeFileSync(PACKAGE_FILE, JSON.stringify(pkg, null, 4) + '\n');
    console.log('\npackage.json updated.');

    // Output for GitHub Actions
    if (process.env.GITHUB_OUTPUT) {
      fs.appendFileSync(process.env.GITHUB_OUTPUT, `updated=true\n`);
      const summary = changes.join('\n');
      fs.appendFileSync(
        process.env.GITHUB_OUTPUT,
        `changes<<EOF\n${summary}\nEOF\n`
      );
    }
  } else {
    console.log('\nAll plugins are up to date.');
    if (process.env.GITHUB_OUTPUT) {
      fs.appendFileSync(process.env.GITHUB_OUTPUT, `updated=false\n`);
    }
  }
})();