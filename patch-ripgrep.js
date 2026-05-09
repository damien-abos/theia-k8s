const fs = require('fs');
const file = 'node_modules/@theia/native-webpack-plugin/lib/native-webpack-plugin.js';
let content = fs.readFileSync(file, 'utf8');
const before = content;

content = content.replace(
  /require\.resolve\(`@vscode\/ripgrep\/bin\/rg\$\{suffix\}`, \{ paths: \[issuer\] \}\)/,
  "require('path').join(process.cwd(), 'node_modules/@vscode/ripgrep/bin', `rg${suffix}`)"
);

if (content === before) {
  console.error('PATCH FAILED: pattern not found');
  process.exit(1);
}
fs.writeFileSync(file, content);
console.log('PATCH OK');