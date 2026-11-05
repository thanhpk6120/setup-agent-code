# Angular Unittest Commands & Configurations

## 1. Identify Impact Scope (Git Diff)

Get list of recently changed files:
```bash
git diff --name-only HEAD~1
```

Get detailed diff on a specific file to map changed methods/lines:
```bash
git diff -U0 HEAD~1 -- src/app/path/to/target.component.ts
```

## 2. Selective Test Execution Commands

Run tests for a specific `.spec.ts` file in headless mode and generate coverage:
```bash
ng test --include="src/app/path/to/target.component.spec.ts" --no-watch --code-coverage --browsers=ChromeHeadless
```

Run tests for a feature directory:
```bash
ng test --include="src/app/features/target/**/*.spec.ts" --no-watch --code-coverage --browsers=ChromeHeadless
```

*CLI Flags Notes:*
- `--include="path/to/*.spec.ts"`: Restricts executed test files, optimizing execution speed.
- `--no-watch`: Automatically exits process after completion, suitable for automation and CI.
- `--code-coverage`: Activates coverage collector via Karma/Istanbul.
- `--browsers=ChromeHeadless`: Runs headlessly in the background without launching browser windows.

## 3. Thresholds & Reporters Configuration

### `angular.json` Configuration
Ensure karma builder enables code coverage and excludes unnecessary files:
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

### `karma.conf.js` Configuration
Define default report export directory and report formats:
```javascript
module.exports = function (config) {
  config.set({
    coverageReporter: {
      dir: require('path').join(__dirname, './coverage'),
      subdir: '.',
      reporters: [
        { type: 'html' },
        { type: 'text-summary' },
        { type: 'lcovonly' }
      ]
    }
  });
};
```

## 4. Read & Filter lcov.info Report

Read coverage metrics (Functions, Lines, Branches) for a specific source file from `lcov.info`:
```bash
awk '/SF:.*target.component.ts/,/end_of_record/' coverage/lcov.info
```

Check invocation count for a specific function (FNDA):
```bash
awk '/SF:.*target.component.ts/,/end_of_record/' coverage/lcov.info | grep "FNDA:"
```

## 5. Visual HTML Report

Serve visual HTML report:
```bash
npx serve coverage/index.html
```

## 6. Archive Evidence

Save coverage report and evidence to a zip file once upon completion or stopping:
```powershell
Compress-Archive -Path coverage/* -DestinationPath coverage-evidence.zip -Force
```

## 7. Mock Test Template With `jasmine.createSpyObj`

```typescript
describe('TargetComponent', () => {
  let component: TargetComponent;
  let fixture: ComponentFixture<TargetComponent>;
  let mockService: jasmine.SpyObj<TargetService>;

  beforeEach(async () => {
    mockService = jasmine.createSpyObj('TargetService', ['getData', 'saveData']);
    mockService.getData.and.returnValue(of({ id: 1, name: 'Test' }));

    await TestBed.configureTestingModule({
      declarations: [TargetComponent],
      providers: [{ provide: TargetService, useValue: mockService }]
    }).compileComponents();

    fixture = TestBed.createComponent(TargetComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create component and load initial data', () => {
    expect(component).toBeTruthy();
    expect(mockService.getData).toHaveBeenCalled();
  });
});
```
