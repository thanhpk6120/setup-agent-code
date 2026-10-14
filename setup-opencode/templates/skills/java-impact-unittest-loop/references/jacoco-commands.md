# Jacoco & Test Commands Cheat Sheet

## 1. Run tests and generate the JaCoCo report (specific classes)

### Maven
Run tests for specific classes and export the report:
```bash
mvn -Dtest=com.example.ClassATest,com.example.ClassBTest -Dsurefire.failIfNoSpecifiedTests=false test jacoco:report
```

Run the full test suite and export the report:
```bash
mvn clean test jacoco:report
```

Report file locations:
- `target/site/jacoco/jacoco.xml`
- `target/site/jacoco/index.html`

### Gradle
Run tests for specific classes and export the report:
```bash
./gradlew test --tests "com.example.ClassATest" --tests "com.example.ClassBTest" jacocoTestReport
```

Report file locations:
- `build/reports/jacoco/test/jacocoTestReport.xml`
- `build/reports/jacoco/test/html/index.html`

## 2. Read and compute coverage from jacoco.xml

Counter block structure in `jacoco.xml`:
```xml
<counter type="INSTRUCTION" missed="15" covered="85"/>
<counter type="BRANCH" missed="5" covered="45"/>
<counter type="LINE" missed="4" covered="36"/>
```
Percentage formula: `(covered / (covered + missed)) * 100`

One-line Python script to compute LINE coverage % for one class (e.g. `com/example/TargetClass`):
```bash
python -c "import xml.etree.ElementTree as ET, sys; root = ET.parse(sys.argv[1]).getroot(); n = root.find('.//class[@name=\"com/example/TargetClass\"]'); c = n.find('counter[@type=\"LINE\"]') if n is not None else None; print(f'{int(c.attrib[\"covered\"]) / (int(c.attrib[\"covered\"]) + int(c.attrib[\"missed\"])) * 100:.2f}%' if c is not None else 'Class not found')" target/site/jacoco/jacoco.xml
```

## 3. Automatic threshold check (jacoco-check)

Configure the rule in `pom.xml` (Maven) to check coverage on the affected class (not the whole project):
```xml
<execution>
    <id>jacoco-check</id>
    <goals>
        <goal>check</goal>
    </goals>
    <configuration>
        <includes>
            <include>com/example/TargetClass.class</include>
        </includes>
        <rules>
            <rule>
                <element>CLASS</element>
                <limits>
                    <limit>
                        <counter>INSTRUCTION</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.90</minimum>
                    </limit>
                    <limit>
                        <counter>BRANCH</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.90</minimum>
                    </limit>
                </limits>
            </rule>
        </rules>
    </configuration>
</execution>
```

## 4. 5 minimal Mockito & JUnit5 patterns

Mock dependencies (Service/Repository):
```java
@ExtendWith(MockitoExtension.class)
class TargetClassTest {
    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private UserService userService;
}
```

Stub behavior (when) and verify:
```java
@Test
void testFindUser() {
    when(userRepository.findById(1L)).thenReturn(Optional.of(new User(1L, "Test")));
    
    userService.getUser(1L);
    
    verify(userRepository, times(1)).findById(1L);
}
```

Capture arguments with ArgumentCaptor:
```java
@Test
void testSaveUser() {
    ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
    
    userService.createUser("NewUser");
    
    verify(userRepository).save(captor.capture());
    assertEquals("NewUser", captor.getValue().getName());
}
```

Check exceptions (assertThrows):
```java
@Test
void testUserNotFound() {
    when(userRepository.findById(99L)).thenReturn(Optional.empty());
    
    assertThrows(UserNotFoundException.class, () -> {
        userService.getUser(99L);
    });
}
```

Boundary tests with @ParameterizedTest:
```java
@ParameterizedTest
@CsvSource({"0, false", "-1, false", "18, true"})
void testAgeValidation(int age, boolean expected) {
    assertEquals(expected, userService.isValidAge(age));
}
```

## 5. Anti-patterns (Forbidden)

1. Do not edit `src/main` source (e.g. deleting hard-to-test logic, changing variable access) just to ease testing and raise coverage.
2. Do not lower the threshold (below 0.90) to bypass the CI pipeline instead of adding tests for missing cases.
3. Do not add affected or logic-changed classes to the JaCoCo plugin `exclude` list to hide missing tests.

## 6. Archive evidence

Run after the loop finishes/exits:
```bash
mkdir -p evidence
# With Maven:
zip -r evidence/java-final-coverage.zip target/site/jacoco/
# With Gradle:
zip -r evidence/java-final-coverage.zip build/reports/jacoco/test/
```