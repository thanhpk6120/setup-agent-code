# React Test & Coverage Commands Cheat Sheet

Real commands executed in the React Vitest / Jest workflow.

---

## 1. Git diff: identify changed lines and functions

### List of modified files
```bash
git status -s
git diff --name-only HEAD~1 -- "src/**/*.{ts,tsx,js,jsx}"
```

### Get changed line ranges (hunks)
```bash
# -U0 drops surrounding context lines to keep exactly the changed lines
git diff -U0 HEAD~1 -- "src/components/MyComponent.tsx"
```

### Extract changed functions and line ranges with Node.js
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

## 2. Run selective tests (Selective Testing)

Run only tests related to changed files, never the full suite.

### Vitest (v8 / istanbul)
```bash
# 1. Run the exact test file with coverage (lcov/json reporters are required because Vitest v8 does not emit lcov by itself)
npx vitest run src/components/MyComponent.test.tsx --coverage --coverage.reporter=lcov --coverage.reporter=json

# 2. Auto-find and run tests related to the edited source file
npx vitest related src/components/MyComponent.tsx --run --coverage --coverage.reporter=lcov --coverage.reporter=json
```

### Jest
```bash
# 1. Run one test file and collect coverage only for that component file
npx jest src/components/MyComponent.test.tsx --coverage --collectCoverageFrom="src/components/MyComponent.tsx"

# 2. Find tests related to the changed file
npx jest --findRelatedTests src/components/MyComponent.tsx --coverage --collectCoverageFrom="src/components/MyComponent.tsx"
```

### Default coverage file locations
- HTML: `coverage/index.html` (Vitest) or `coverage/lcov-report/index.html` (Jest)
- LCOV: `coverage/lcov.info`
- JSON: `coverage/coverage-final.json`

---

## 3. Filter and compute coverage on changed functions/lines

Because Vitest and Jest have no built-in `--changed-lines-coverage`, parse `coverage/lcov.info` or `coverage/coverage-final.json` using the line ranges from the git diff.

### Node.js script computing Statement, Branch & Function coverage from lcov.info
```bash
# Save as check-coverage.js and run: node check-coverage.js <file-path> <start-line> <end-line> [lcov-path]
# Or run directly via node -e as below:
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
let fnMap = {}; // name -> { line, hit }
const normalizePath = (p) => p.replace(/\\\\/g, '/');

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

console.log(\`[Changed-Lines Coverage] \${targetFile} (Lines \${startLine}-\${endLine})\`);
console.log(\`- Line: \${linePct}% (\${linesHit}/\${linesTotal})\`);
console.log(\`- Branch: \${branchPct}% (\${branchHit}/\${branchTotal})\`);
console.log(\`- Function: \${fnPct}% (\${fnHit}/\${fnTotal})\`);
console.log(Number(linePct) >= 90 && Number(branchPct) >= 90 && Number(fnPct) >= 90 ? '=> PASS (>= 90%)' : '=> FAIL (< 90%)');
" "src/components/MyComponent.tsx" 15 35
```

### Node.js script computing from coverage-final.json (alternative)
```bash
node -e "
const fs = require('fs');
const args = process.argv[1] && process.argv[1].endsWith('.js') ? process.argv.slice(2) : process.argv.slice(1);
const [targetFile, startLine, endLine, jsonPath] = [args[0], parseInt(args[1], 10), parseInt(args[2], 10), args[3] || 'coverage/coverage-final.json'];

if (!fs.existsSync(jsonPath)) process.exit(1);
const covData = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const normalizePath = (p) => p.replace(/\\\\/g, '/');
const fileKey = Object.keys(covData).find(k => normalizePath(k).includes(normalizePath(targetFile)));
if (!fileKey) { console.log('File not found in coverage'); process.exit(0); }

const fileCov = covData[fileKey];
let stTotal=0, stHit=0, brTotal=0, brHit=0, fnTotal=0, fnHit=0;

for(const [k, v] of Object.entries(fileCov.statementMap)) {
  if(v.start.line >= startLine && v.start.line <= endLine) {
     stTotal++;
     if(fileCov.s[k] > 0) stHit++;
  }
}

for(const [k, v] of Object.entries(fileCov.branchMap)) {
  if(v.loc.start.line >= startLine && v.loc.start.line <= endLine) {
     fileCov.b[k].forEach(hit => {
       brTotal++;
       if(hit > 0) brHit++;
     });
  }
}

for(const [k, v] of Object.entries(fileCov.fnMap)) {
  if(v.decl.start.line >= startLine && v.decl.start.line <= endLine) {
     fnTotal++;
     if(fileCov.f[k] > 0) fnHit++;
  }
}

const stPct = stTotal ? ((stHit/stTotal)*100).toFixed(2) : '100.00';
const brPct = brTotal ? ((brHit/brTotal)*100).toFixed(2) : '100.00';
const fnPct = fnTotal ? ((fnHit/fnTotal)*100).toFixed(2) : '100.00';

console.log(\`[Coverage JSON] \${targetFile} (Lines \${startLine}-\${endLine})\`);
console.log(\`- Statement: \${stPct}% (\${stHit}/\${stTotal})\`);
console.log(\`- Branch: \${brPct}% (\${brHit}/\${brTotal})\`);
console.log(\`- Function: \${fnPct}% (\${fnHit}/\${fnTotal})\`);
" "src/components/MyComponent.tsx" 15 35
```

## 4. View the HTML report (open in browser)

### Open the HTML file directly
- **Windows (CMD/PowerShell)**:
  ```cmd
  start coverage/index.html
  ```
- **macOS**:
  ```bash
  open coverage/index.html
  ```
- **Linux**:
  ```bash
  xdg-open coverage/index.html
  ```

### Open via a local server (when CORS/file-URL limits apply)
```bash
# Using serve
npx serve coverage -p 3000

# Or use Vite preview if the matching build directory is configured
npx vite preview --outDir coverage
```

---

## 5. Archive evidence

Create the `evidence/` directory and archive artifacts exactly once at the end:

### Linux / macOS
```bash
mkdir -p evidence
zip -r evidence/react-final-coverage.zip coverage/
```

### Windows (PowerShell)
```powershell
if (!(Test-Path -Path "evidence")) { New-Item -ItemType Directory -Path "evidence" }
Compress-Archive -Path coverage -DestinationPath evidence/react-final-coverage.zip -Force
```

### Cross-platform (Node.js script needs no extra tools)
```bash
node -e "
const fs = require('fs');
const { execSync } = require('child_process');
if (!fs.existsSync('evidence')) fs.mkdirSync('evidence');
const isWin = process.platform === 'win32';
const cmd = isWin
  ? 'powershell Compress-Archive -Path coverage -DestinationPath evidence/react-final-coverage.zip -Force'
  : 'zip -r evidence/react-final-coverage.zip coverage/';
execSync(cmd, { stdio: 'inherit' });
"
```

---

## 6. Standard mock patterns in Vitest / Testing Library

### Mock Function & Spy
```tsx
import { vi } from 'vitest';

const onClick = vi.fn();
const fetchSpy = vi.spyOn(api, 'getUser').mockResolvedValue({ id: 1, name: 'Alice' });
```

### Mock child components (reduce dependent logic)
```tsx
vi.mock('./ComplexChild', () => ({
  default: () => <div data-testid="mock-child">Mocked Child</div>
}));
```

### Mock Browser API (LocalStorage, ResizeObserver)
```tsx
vi.stubGlobal('localStorage', {
  getItem: vi.fn(),
  setItem: vi.fn(),
  removeItem: vi.fn(),
  clear: vi.fn(),
});
```
