# .NET Test & Coverage Commands Cheat Sheet

## 1. Map Git Diff to changed C# methods

Show changes with C# method names in hunk headers:
```bash
# Show diff with function context
git diff -W src/

# Show change hunks without context lines, with method names visible in the @@ header
git diff -U0 HEAD~1 -- "*.cs"
```

List recently modified C# files:
```bash
git diff --name-only HEAD~1 -- "*.cs"
```

---

## 2. Run selective tests (dotnet test --filter)

Run all tests in one Test Class:
```bash
dotnet test --filter "FullyQualifiedName~MyNamespace.Services.OrderServiceTests"
```

Run one specific test method:
```bash
dotnet test --filter "FullyQualifiedName=MyNamespace.Services.OrderServiceTests.CreateOrder_ValidInput_ReturnsSuccess"
```

Run a combination of classes or namespaces:
```bash
dotnet test --filter "FullyQualifiedName~OrderServiceTests|FullyQualifiedName~PaymentServiceTests"
```

---

## 3. Collect coverage with Coverlet (XPlat Code Coverage)

Run selective tests with the coverage flag (generates `coverage.cobertura.xml` by default):
```bash
dotnet test --filter "FullyQualifiedName~OrderServiceTests" --collect "XPlat Code Coverage"
```
Report file is created at: `[ProjectTestDir]/TestResults/{guid}/coverage.cobertura.xml`

Set the Coverlet threshold (90% Line & Branch):
```bash
dotnet test --collect "XPlat Code Coverage" -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Threshold=90 DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.ThresholdType="line,branch"
```

---

## 4. Filter coverage.cobertura.xml by method

Method block structure in the Coverlet-generated Cobertura file:
```xml
<class name="MyNamespace.Services.OrderService" ...>
  <methods>
    <method name="CreateOrderAsync" signature="(...)" line-rate="0.95" branch-rate="0.90">
      <lines>
        <line number="45" hits="3" branch="False"/>
        <line number="48" hits="0" branch="True" condition-coverage="50% (1/2)"/>
      </lines>
    </method>
  </methods>
</class>
```

### Filter with PowerShell (native on Windows):
```powershell
$xml = [xml](Get-Content (Get-ChildItem -Recurse -Filter "coverage.cobertura.xml" | Select -First 1).FullName)
$method = $xml.SelectSingleNode("//class[@name='MyNamespace.Services.OrderService']/methods/method[@name='CreateOrderAsync']")
if ($method) {
    [PSCustomObject]@{
        Method = $method.name
        LineRate = "{0:P2}" -f [double]$method.'line-rate'
        BranchRate = "{0:P2}" -f [double]$method.'branch-rate'
    } | Format-Table
} else {
    Write-Host "Method not found"
}
```

### Filter with Python (cross-platform):
```bash
python -c "import xml.etree.ElementTree as ET, glob; f = glob.glob('**/coverage.cobertura.xml', recursive=True)[0]; root = ET.parse(f).getroot(); m = root.find('.//class[@name=\"MyNamespace.Services.OrderService\"]/methods/method[@name=\"CreateOrderAsync\"]'); print(f'Line: {float(m.attrib[\"line-rate\"])*100:.1f}%, Branch: {float(m.attrib[\"branch-rate\"])*100:.1f}%') if m is not None else print('Method not found')"
```

---

## 5. Generate a visual HTML report (ReportGenerator)

Install the ReportGenerator global tool (if missing):
```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
```

Generate the HTML report from the Cobertura file:
```bash
reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html
```

---

## 6. Open the HTML report and package the final result

### Open the HTML report in a browser:
```powershell
# On Windows / PowerShell
Start-Process "coveragereport\index.html"

# On Linux/macOS
xdg-open coveragereport/index.html || open coveragereport/index.html
```

### Archive the report directory as ZIP (do exactly once at the end):
Create the `evidence` directory if missing and save the archive as `dotnet-final-coverage.zip`.

```powershell
# PowerShell
New-Item -ItemType Directory -Force -Path evidence
Compress-Archive -Path "coveragereport\*" -DestinationPath "evidence\dotnet-final-coverage.zip" -Force

# Bash / Linux
mkdir -p evidence
zip -r evidence/dotnet-final-coverage.zip coveragereport/
```

---

## 7. Standard xUnit & Moq / NSubstitute samples

### Mock sample with Moq:
```csharp
public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _repoMock;
    private readonly OrderService _sut; // System Under Test

    public OrderServiceTests()
    {
        _repoMock = new Mock<IOrderRepository>();
        _sut = new OrderService(_repoMock.Object);
    }

    [Fact]
    public async Task CreateOrderAsync_ValidOrder_ReturnsId()
    {
        // Arrange
        var order = new Order { Amount = 100 };
        _repoMock.Setup(r => r.SaveAsync(It.IsAny<Order>())).ReturnsAsync(1);

        // Act
        var result = await _sut.CreateOrderAsync(order);

        // Assert
        Assert.Equal(1, result);
        _repoMock.Verify(r => r.SaveAsync(It.IsAny<Order>()), Times.Once);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-10)]
    public async Task CreateOrderAsync_InvalidAmount_ThrowsArgumentException(decimal amount)
    {
        var order = new Order { Amount = amount };
        await Assert.ThrowsAsync<ArgumentException>(() => _sut.CreateOrderAsync(order));
    }
}
```

### Mock sample with NSubstitute:
```csharp
public class OrderServiceTests
{
    private readonly IOrderRepository _repo = Substitute.For<IOrderRepository>();
    private readonly OrderService _sut;

    public OrderServiceTests()
    {
        _sut = new OrderService(_repo);
    }

    [Fact]
    public async Task CreateOrderAsync_ValidOrder_CallsSave()
    {
        var order = new Order { Amount = 50 };
        _repo.SaveAsync(Arg.Any<Order>()).Returns(Task.FromResult(1));

        var result = await _sut.CreateOrderAsync(order);

        Assert.Equal(1, result);
        await _repo.Received(1).SaveAsync(Arg.Any<Order>());
    }
}
```

---

## 8. Anti-patterns (Forbidden)

1. Do not change access modifiers in `src` (e.g. `private` to `public` or `internal`) just to ease testing; test through the public contract instead.
2. Do not put `[Fact(Skip = "...")]` on failing test cases to beautify pass/coverage rates.
3. Do not run `dotnet test` on the whole solution when only 1 method in 1 class changed. Always use `--filter` to keep feedback under 5 seconds.
