# .NET Test & Coverage Commands Cheat Sheet

## 1. Map Git Diff to Changed C# Methods

Inspect changes with C# method context in hunk headers:
```bash
# Show diff with function context
git diff -W src/

# Show diff blocks without context lines, showing method names in @@ header
git diff -U0 HEAD~1 -- "*.cs"
```

List recently modified C# files:
```bash
git diff --name-only HEAD~1 -- "*.cs"
```

---

## 2. Run Selective Tests (dotnet test --filter)

Run all tests in a Test Class:
```bash
dotnet test --filter "FullyQualifiedName~MyNamespace.Services.OrderServiceTests"
```

Run a specific test method:
```bash
dotnet test --filter "FullyQualifiedName=MyNamespace.Services.OrderServiceTests.CreateOrder_ValidInput_ReturnsSuccess"
```

Combine multiple classes or namespaces:
```bash
dotnet test --filter "FullyQualifiedName~OrderServiceTests|FullyQualifiedName~PaymentServiceTests"
```

---

## 3. Collect Coverage with Coverlet (XPlat Code Coverage)

Run selective tests with coverage collection enabled (defaults to `coverage.cobertura.xml`):
```bash
dotnet test --filter "FullyQualifiedName~OrderServiceTests" --collect "XPlat Code Coverage"
```
Report file is generated at: `[ProjectTestDir]/TestResults/{guid}/coverage.cobertura.xml`

Set Coverlet Threshold (90% Line & Branch):
```bash
dotnet test --collect "XPlat Code Coverage" -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Threshold=90 DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.ThresholdType="line,branch"
```

---

## 4. Filter coverage.cobertura.xml by Method

Method block structure in Coverlet-generated Cobertura files:
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

### Filter using PowerShell (Native Windows):
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

### Filter using Python (Cross-platform):
```bash
python -c "import xml.etree.ElementTree as ET, glob; f = glob.glob('**/coverage.cobertura.xml', recursive=True)[0]; root = ET.parse(f).getroot(); m = root.find('.//class[@name="MyNamespace.Services.OrderService"]/methods/method[@name="CreateOrderAsync"]'); print(f'Line: {float(m.attrib["line-rate"])*100:.1f}%, Branch: {float(m.attrib["branch-rate"])*100:.1f}%') if m is not None else print('Method not found')"
```

---

## 5. Visual HTML Report (ReportGenerator)

Install ReportGenerator global tool (if missing):
```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
```

Generate HTML report from Cobertura file:
```bash
reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html
```

---

## 6. Open HTML Report and Package Final Artifact

### Open HTML report in browser:
```powershell
# Windows / PowerShell
Start-Process "coveragereport\index.html"

# Linux/macOS
xdg-open coveragereport/index.html || open coveragereport/index.html
```

### Compress report directory into ZIP (once at end of procedure):
Create `evidence` folder if missing and save as `dotnet-final-coverage.zip`.

```powershell
# PowerShell
New-Item -ItemType Directory -Force -Path evidence
Compress-Archive -Path "coveragereport\*" -DestinationPath "evidence\dotnet-final-coverage.zip" -Force

# Bash / Linux
mkdir -p evidence
zip -r evidence/dotnet-final-coverage.zip coveragereport/
```

---

## 7. Standard xUnit & Moq / NSubstitute Patterns

### Moq Pattern:
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

### NSubstitute Pattern:
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

## 8. Anti-patterns (Strictly Forbidden)

1. Modifying access modifiers in `src` (changing `private` to `public` or `internal`) merely to facilitate tests instead of testing via the public contract.
2. Placing `[Fact(Skip = "...")]` on failing test cases to inflate pass/coverage numbers.
3. Running `dotnet test` on the entire solution when only 1 method in 1 class changed. Always use `--filter` to keep feedback latency under 5 seconds.
