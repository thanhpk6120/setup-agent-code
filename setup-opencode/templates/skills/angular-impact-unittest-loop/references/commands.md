# Angular Unittest Commands & Configurations

## 1. Identify impact scope (Git Diff)

List the most recently changed files:
```bash
git diff --name-only HEAD~1
```

Show details of changes in a specific file to map changed methods/lines:
```bash
git diff -U0 HEAD~1 -- src/app/path/to/target.component.ts
```

## 2. Selective test commands (Selective Test)

Run one specific `.spec.ts` file headless with coverage:
```bash
ng test --include="src/app/path/to/target.component.spec.ts" --no-watch --code-coverage --browsers=ChromeHeadless
```

Run tests for one feature directory:
```bash
ng test --include="src/app/features/target/**/*.spec.ts" --no-watch --code-coverage --browsers=ChromeHeadless
```

*CLI flag notes:*
- `--include="path/to/*.spec.ts"`: limit executed test files, optimize speed.
- `--no-watch`: exit the process when done, for automation and CI.
- `--code-coverage`: enable coverage collection via Karma/Istanbul.
- `--browsers=ChromeHeadless`: run headless in the background without a browser window.

## 3. Threshold and reporter configuration

### `angular.json` configuration
Ensure the karma builder enables code coverage and excludes unneeded files:
```json
"test": {
  "builder": "@angular-devkit/build-angular:karma",
  "options": {
    "codeCoverage": true,
    "codeCoverageExclude": [
      "src/environments/**",
      "src/main.ts",
      "src/polyfills.ts"
    ]
  }
}
```

### `karma.conf.js` configuration
Define the default report output directory and report formats:
```javascript
module.exports = function (config) {
  config.set({
    coverageReporter: {
      dir: require('path').join(__dirname, './coverage/<project-name>'),
      subdir: '.',
      reporters: [
        { type: 'html' },
        { type: 'lcovonly' }
      ],
      check: {
        global: {
          statements: 90,
          branches: 90,
          functions: 90,
          lines: 90
        }
      }
    }
  });
};
```

## 4. Read and filter the lcov.info report

Read coverage metrics (Functions, Lines, Branches) for one source file from `lcov.info`:
```bash
node -e "const fs=require('fs');const p=process.argv[2];const b=fs.readFileSync(process.argv[1],'utf8').split('end_of_record').find(x=>x.includes('SF:'+p));if(b){const m=(r)=>b.match(r)?.[1]||'0';const fnf=m(/FNF:(\d+)/),fnh=m(/FNH:(\d+)/);const lf=m(/LF:(\d+)/),lh=m(/LH:(\d+)/);const brf=m(/BRF:(\d+)/),brh=m(/BRH:(\d+)/);console.log('Functions: %s/%s (%s%)',fnh,fnf,fnf>0?((fnh/fnf)*100).toFixed(1):'100');console.log('Lines: %s/%s (%s%)',lh,lf,lf>0?((lh/lf)*100).toFixed(1):'100');console.log('Branches: %s/%s (%s%)',brh,brf,brf>0?((brh/brf)*100).toFixed(1):'100');}else{console.log('File not found in lcov');}" coverage/<project-name>/lcov.info src/app/path/to/target.component.ts
```

Check how often a specific function is called (FNDA):
```bash
node -e "const fs=require('fs');const b=fs.readFileSync(process.argv[1],'utf8').split('end_of_record').find(x=>x.includes('SF:'+process.argv[2]));if(b){const lines=b.split('\n').filter(l=>l.startsWith('FNDA:')&&l.includes(process.argv[3]));console.log(lines.length?lines.join('\n'):'0 hits');}else{console.log('File not found');}" coverage/<project-name>/lcov.info src/app/path/to/target.component.ts targetMethodName
```

## 5. Open the visual HTML report

```bash
# Windows
start coverage/<project-name>/index.html

# Linux
xdg-open coverage/<project-name>/index.html

# MacOS
open coverage/<project-name>/index.html
```

## 6. Archive evidence

Save the coverage report and evidence into a zip file exactly once on success or at the final stop:
```bash
mkdir -p evidence
zip -r evidence/angular-final-coverage.zip coverage/
```

## 7. Mock setup sample with `jasmine.createSpyObj`

```typescript
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { TargetComponent } from './target.component';
import { DataService } from './data.service';

describe('TargetComponent', () => {
  let component: TargetComponent;
  let fixture: ComponentFixture<TargetComponent>;
  let mockDataService: jasmine.SpyObj<DataService>;

  beforeEach(async () => {
    mockDataService = jasmine.createSpyObj('DataService', ['getData', 'updateData']);

    await TestBed.configureTestingModule({
      declarations: [TargetComponent],
      providers: [
        { provide: DataService, useValue: mockDataService }
      ]
    }).compileComponents();

    fixture = TestBed.createComponent(TargetComponent);
    component = fixture.componentInstance;
  });

  it('should handle happy path', () => {
    mockDataService.getData.and.returnValue(of({ id: 1, name: 'Sample' }));
    component.loadData();
    expect(mockDataService.getData).toHaveBeenCalled();
    expect(component.data).toBeDefined();
  });

  it('should handle error branch', () => {
    mockDataService.getData.and.returnValue(throwError(() => new Error('Server Error')));
    component.loadData();
    expect(component.hasError).toBeTrue();
  });
});
```