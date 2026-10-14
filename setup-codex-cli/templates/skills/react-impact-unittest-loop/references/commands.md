# React Test & Coverage Commands Cheat Sheet

Commands cheat sheet for Vitest / Jest testing workflows in React.

---

## 1. Identify Changed Lines & Functions with Git Diff

### List modified files
```bash
git status -s
git diff --name-only HEAD~1 -- "src/**/*.{ts,tsx,js,jsx}"
```

### Get modified line hunks
```bash
# -U0 removes context lines to show exact changed lines
git diff -U0 HEAD~1 -- "src/components/MyComponent.tsx"
```

### Extract functions & line ranges using Node.js
```bash
node -e "
const { execSync } = require('child_process');
const diff = execSync('git diff -U0 HEAD~1 -- \"src/**/*.{ts,tsx,js,jsx}\"', { encoding: 'utf-8' });
const hunks = [];
let currentFile = '';

for (const line of diff.split('\n')) {
  if (line.startsWith('+++ b/')) {
    currentFile = line.replace('+++ b/', '').trim();
  } else if (line.startsWith('@@')) {
    const match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/);
    if (match) {
      const start = parseInt(match[1], 10);
      const count = match[2] !== undefined ? parseInt(match[2], 10) : 1;
      hunks.push({ file: currentFile, start, end: start + Math.max(count - 1, 0), header: line });
    }
  }
}
console.table(hunks);
"
```

---

## 2. Run Selective Tests

Run only tests relevant to the modified file; do not run full suite.

### Vitest (v8 / istanbul)
```bash
# Run specific test file with coverage
npx vitest run src/components/MyComponent.test.tsx --coverage --coverage.reporter=lcov --coverage.reporter=json

# Automatically find and run tests related to modified source file
npx vitest related src/components/MyComponent.tsx --run --coverage --coverage.reporter=lcov --coverage.reporter=json
```

### Jest
```bash
# Run specific test file collecting coverage on target component
npx jest src/components/MyComponent.test.tsx --coverage --collectCoverageFrom="src/components/MyComponent.tsx"

# Find related tests
npx jest --findRelatedTests src/components/MyComponent.tsx --coverage --collectCoverageFrom="src/components/MyComponent.tsx"
```

### Default coverage report paths
- HTML: `coverage/index.html` (Vitest) or `coverage/lcov-report/index.html` (Jest)
- LCOV: `coverage/lcov.info`
- JSON: `coverage/coverage-final.json`

---

## 3. Filter and Calculate Coverage on Changed Lines

Calculate Statement, Branch & Function coverage strictly for the changed line range by parsing `coverage/lcov.info` or `coverage/coverage-final.json`.

### Node.js script calculating coverage from lcov.info
```bash
node -e "
const fs = require('fs');
const args = process.argv[1] && process.argv[1].endsWith('.js') ? process.argv.slice(2) : process.argv.slice(1);
const [targetFile, startLine, endLine, lcovPath] = [
  args[0],
  parseInt(args[1], 10),
  parseInt(args[2], 10),
  args[3] || 'coverage/lcov.info'
];

if (!fs.existsSync(lcovPath)) {
  console.error('lcov file not found:', lcovPath);
  process.exit(1);
}

const content = fs.readFileSync(lcovPath, 'utf8');
const lines = content.split('\n');

let inFile = false;
let linesTotal = 0, linesHit = 0;
let branchTotal = 0, branchHit = 0;
let fnMap = {};
const normalizePath = (p) => p.replace(/\\/g, '/');

for (const line of lines) {
  if (line.startsWith('SF:') && normalizePath(line).includes(normalizePath(targetFile))) {
    inFile = true;
  } else if (line === 'end_of_record') {
    inFile = false;
  } else if (inFile) {
    if (line.startsWith('DA:')) {
      const [lineNum, hitCount] = line.slice(3).split(',').map(Number);
      if (lineNum >= startLine && lineNum <= endLine) {
        linesTotal++;
        if (hitCount > 0) linesHit++;
      }
    } else if (line.startsWith('BRDA:')) {
      const parts = line.slice(5).split(',');
      const lineNum = Number(parts[0]);
      const taken = parts[3];
      if (lineNum >= startLine && lineNum <= endLine) {
        branchTotal++;
        if (taken !== '-' && Number(taken) > 0) branchHit++;
      }
    } else if (line.startsWith('FN:')) {
      const [ln, name] = line.slice(3).split(',');
      fnMap[name] = { line: Number(ln), hit: 0 };
    } else if (line.startsWith('FNDA:')) {
      const [hit, name] = line.slice(5).split(',');
      if (fnMap[name]) fnMap[name].hit = Number(hit);
    }
  }
}

let fnTotal = 0, fnHit = 0;
for (const [name, data] of Object.entries(fnMap)) {
  if (data.line >= startLine && data.line <= endLine) {
    fnTotal++;
    if (data.hit > 0) fnHit++;
  }
}

const linePct = linesTotal ? ((linesHit / linesTotal) * 100).toFixed(2) : '100.00';
const branchPct = branchTotal ? ((branchHit / branchTotal) * 100).toFixed(2) : '100.00';
const fnPct = fnTotal ? ((fnHit / fnTotal) * 100).toFixed(2) : '100.00';

console.log(\`[Coverage Changed Lines] \${targetFile} (Lines \${startLine}-\${endLine})\`);
console.log(\`- Line: \${linePct}% (\${linesHit}/\${linesTotal})\`);
console.log(\`- Branch: \${branchPct}% (\${branchHit}/\${branchTotal})\`);
console.log(\`- Function: \${fnPct}% (\${fnHit}/\${fnTotal})\`);
console.log(Number(linePct) >= 90 && Number(branchPct) >= 90 && Number(fnPct) >= 90 ? '=> PASS (>= 90%)' : '=> FAIL (< 90%)');
" "src/components/MyComponent.tsx" 15 35
```

---

## 4. Visual HTML Report

### Open HTML file directly
- **Windows (CMD/PowerShell)**: `start coverage/index.html`
- **macOS**: `open coverage/index.html`
- **Linux**: `xdg-open coverage/index.html`

### Open via Local Server
```bash
npx serve coverage -p 3000
```

---

## 5. Archive Evidence

Create `evidence/` directory and compress artifact once at end of procedure:

```bash
mkdir -p evidence
zip -r evidence/react-final-coverage.zip coverage/
```

PowerShell:

```powershell
if (!(Test-Path -Path "evidence")) { New-Item -ItemType Directory -Path "evidence" }
Compress-Archive -Path coverage -DestinationPath evidence/react-final-coverage.zip -Force
```

---

## 6. Standard Mocks in Vitest / Testing Library

```tsx
import { vi } from 'vitest';

const onClick = vi.fn();
const fetchSpy = vi.spyOn(api, 'getUser').mockResolvedValue({ id: 1, name: 'Alice' });

vi.mock('./ComplexChild', () => ({
  default: () => <div data-testid="mock-child">Mocked Child</div>
}));

vi.stubGlobal('localStorage', {
  getItem: vi.fn(),
  setItem: vi.fn(),
  removeItem: vi.fn(),
  clear: vi.fn(),
});
```
