# JaCoCo & Test Commands Cheat Sheet

## 1. Run Tests and Generate JaCoCo Report (Targeted Class)

### Maven
Run tests for specific classes and output report:
```bash
mvn -Dtest=com.example.ClassATest,com.example.ClassBTest -Dsurefire.failIfNoSpecifiedTests=false test jacoco:report
```

Run full test suite and output report:
```bash
mvn clean test jacoco:report
```

Report file locations:
- `target/site/jacoco/jacoco.xml`
- `target/site/jacoco/index.html`

### Gradle
Run tests for specific classes and output report:
```bash
./gradlew test --tests "com.example.ClassATest" --tests "com.example.ClassBTest" jacocoTestReport
```

Report file locations:
- `build/reports/jacoco/test/jacocoTestReport.xml`
- `build/reports/jacoco/test/html/index.html`

## 2. Read and Calculate Coverage from jacoco.xml

Counter block structure in `jacoco.xml`:
```xml
<counter type="INSTRUCTION" missed="15" covered="85"/>
<counter type="BRANCH" missed="5" covered="45"/>
<counter type="LINE" missed="4" covered="36"/>
```
Percentage formula: `(covered / (covered + missed)) * 100`

One-line Python script to calculate % LINE coverage of a class (e.g. `com/example/TargetClass`):
```bash
python -c "import xml.etree.ElementTree as ET, sys; root = ET.parse(sys.argv[1]).getroot(); n = root.find('.//class[@name="com/example/TargetClass"]'); c = n.find('counter[@type="LINE"]') if n is not None else None; print(f'{int(c.attrib["covered"]) / (int(c.attrib["covered"]) + int(c.attrib["missed"])) * 100:.2f}%' if c is not None else 'Class not found')" target/site/jacoco/jacoco.xml
```

## 3. Automated Check Threshold (jacoco-check)

Configure rule in `pom.xml` (Maven) to check coverage on affected classes (not project-wide):
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

## 4. Minimum 5 Mockito & JUnit 5 Patterns

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

Behavior simulation (when) and verification (verify):
```java
@Test
void testFindUser() {
    when(userRepository.findById(1L)).thenReturn(Optional.of(new User(1L, "Test")));

    userService.getUser(1L);

    verify(userRepository, times(1)).findById(1L);
}
```

Capture arguments via ArgumentCaptor:
```java
@Test
void testSaveUser() {
    ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);

    userService.createUser("NewUser");

    verify(userRepository).save(captor.capture());
    assertEquals("NewUser", captor.getValue().getName());
}
```

Verify Exceptions (assertThrows):
```java
@Test
void testUserNotFound() {
    when(userRepository.findById(99L)).thenReturn(Optional.empty());

    assertThrows(UserNotFoundException.class, () -> {
        userService.getUser(99L);
    });
}
```

Boundary testing with @ParameterizedTest:
```java
@ParameterizedTest
@CsvSource({"0, false", "-1, false", "18, true"})
void testAgeValidation(int age, boolean expected) {
    assertEquals(expected, userService.isValidAge(age));
}
```

## 5. Anti-patterns (Strictly Forbidden)

1. Modifying source code in `src/main` (such as deleting hard-to-test logic, changing variable access) merely to make tests easier to write.
2. Lowering threshold (from 0.90 to lower) to bypass CI pipelines instead of adding tests for missing cases.
3. Adding affected or changed classes to the JaCoCo plugin `exclude` list to conceal missing tests.

## 6. Archive Evidence

Execute after completing or exiting the loop:
```bash
mkdir -p evidence
# Maven:
zip -r evidence/java-final-coverage.zip target/site/jacoco/
# Gradle:
zip -r evidence/java-final-coverage.zip build/reports/jacoco/test/
```
