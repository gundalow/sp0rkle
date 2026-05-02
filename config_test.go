package main_test

// config_test.go validates infrastructure configuration files for consistency.
// These tests guard against version drift between go.mod, .github/workflows/go.yml,
// and the Dockerfile, as well as ensuring the CI test package list stays accurate.

import (
	"bufio"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// repoRoot returns the absolute path to the repository root by walking up from
// this test file's location.
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Dir(file)
}

// readLines reads all lines of a file and returns them as a slice.
func readLines(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open %s: %v", path, err)
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("scan %s: %v", path, err)
	}
	return lines
}

// findLine returns the first line containing the given substring, or ("", false).
func findLine(lines []string, substr string) (string, bool) {
	for _, l := range lines {
		if strings.Contains(l, substr) {
			return l, true
		}
	}
	return "", false
}

// expectedGoVersion is the canonical Go version that must appear in every
// configuration file. Updating this constant is the single source of truth.
const expectedGoVersion = "1.25"

// expectedDockerBaseImage is the full image name used in the Dockerfile build stage.
const expectedDockerBaseImage = "golang:1.25"

// expectedTestPackages is the ordered list of packages that the CI test step
// must exercise. This mirrors the explicit list in go.yml and prevents packages
// with tests from being accidentally omitted.
var expectedTestPackages = []string{
	"./bot",
	"./collections/reminders",
	"./collections/seen",
	"./db",
	"./drivers/decisiondriver",
	"./drivers/factdriver",
	"./drivers/karmadriver",
	"./util",
	"./util/bson",
	"./util/calc",
	"./util/datetime",
}

// ---- go.yml tests ----------------------------------------------------------

func TestGoWorkflowGoVersion(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	line, ok := findLine(lines, "go-version:")
	if !ok {
		t.Fatal("go-version field not found in go.yml")
	}

	if !strings.Contains(line, "'"+expectedGoVersion+"'") {
		t.Errorf("go-version in go.yml = %q; want '1.25'", strings.TrimSpace(line))
	}
}

// TestGoWorkflowTestCommandHasExplicitPackages verifies the test step does not
// use the catch-all ./... pattern.  Using ./... caused CI failures because some
// packages in this repo are intentionally empty and produce build errors.
func TestGoWorkflowTestCommandHasExplicitPackages(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	// Collect the "Test" step's run block – look for the go test invocation.
	testLine, ok := findLine(lines, "go test")
	if !ok {
		t.Fatal("'go test' invocation not found in go.yml")
	}

	if strings.Contains(testLine, "./...") {
		t.Errorf("go test in go.yml uses ./... pattern, which includes empty packages and causes CI failures; use explicit package list instead")
	}
}

func TestGoWorkflowTestPackagesIncluded(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	testLine, ok := findLine(lines, "go test")
	if !ok {
		t.Fatal("'go test' invocation not found in go.yml")
	}

	for _, pkg := range expectedTestPackages {
		if !strings.Contains(testLine, pkg) {
			t.Errorf("expected package %q to be listed in go test command, but it was not found in: %s", pkg, strings.TrimSpace(testLine))
		}
	}
}

// TestGoWorkflowTestPackagesHaveTestFiles verifies that every package listed in
// the CI test command actually contains at least one *_test.go file.
func TestGoWorkflowTestPackagesHaveTestFiles(t *testing.T) {
	root := repoRoot(t)

	for _, pkg := range expectedTestPackages {
		// Strip leading "./" to build a filesystem path.
		relDir := strings.TrimPrefix(pkg, "./")
		dir := filepath.Join(root, filepath.FromSlash(relDir))

		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Errorf("package %s: cannot read directory %s: %v", pkg, dir, err)
			continue
		}

		hasTests := false
		for _, e := range entries {
			if !e.IsDir() && strings.HasSuffix(e.Name(), "_test.go") {
				hasTests = true
				break
			}
		}
		if !hasTests {
			t.Errorf("package %s listed in go.yml test command has no *_test.go files in %s", pkg, dir)
		}
	}
}

// TestGoWorkflowRaceDetectorEnabled checks that the race detector flag (-race)
// is present in the test command so that concurrency bugs are caught in CI.
func TestGoWorkflowRaceDetectorEnabled(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	testLine, ok := findLine(lines, "go test")
	if !ok {
		t.Fatal("'go test' invocation not found in go.yml")
	}

	if !strings.Contains(testLine, "-race") {
		t.Errorf("go test in go.yml is missing -race flag; race detection is required")
	}
}

// TestGoWorkflowCoverageEnabled verifies that coverage reporting flags are present.
func TestGoWorkflowCoverageEnabled(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	testLine, ok := findLine(lines, "go test")
	if !ok {
		t.Fatal("'go test' invocation not found in go.yml")
	}

	if !strings.Contains(testLine, "-coverprofile=coverage.txt") {
		t.Errorf("go test is missing -coverprofile=coverage.txt flag")
	}
	if !strings.Contains(testLine, "-covermode=atomic") {
		t.Errorf("go test is missing -covermode=atomic flag (required with -race)")
	}
}

// TestGoWorkflowNoObsoleteGoVersion is a regression test ensuring the old Go
// versions (1.22, 1.23) that were used before this PR are not referenced in the
// go-version field of the workflow.
func TestGoWorkflowNoObsoleteGoVersion(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))

	obsoleteVersions := []string{"'1.22'", "'1.23'", `"1.22"`, `"1.23"`}
	for _, line := range lines {
		if !strings.Contains(line, "go-version:") {
			continue
		}
		for _, old := range obsoleteVersions {
			if strings.Contains(line, old) {
				t.Errorf("go.yml still references obsolete Go version %s in line: %q", old, strings.TrimSpace(line))
			}
		}
	}
}

// ---- Dockerfile tests ------------------------------------------------------

func TestDockerfileGoVersion(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, "Dockerfile"))

	fromLine, ok := findLine(lines, "FROM golang:")
	if !ok {
		t.Fatal("FROM golang: not found in Dockerfile")
	}

	if !strings.Contains(fromLine, expectedDockerBaseImage) {
		t.Errorf("Dockerfile FROM line = %q; want it to contain %q", strings.TrimSpace(fromLine), expectedDockerBaseImage)
	}
}

// TestDockerfileMultiStageBuild verifies the Dockerfile uses the expected two-stage
// build: a Go build stage and a distroless runtime stage.
func TestDockerfileMultiStageBuild(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, "Dockerfile"))

	_, hasBuildStage := findLine(lines, "as build-env")
	if !hasBuildStage {
		t.Error("Dockerfile missing build stage ('as build-env')")
	}

	_, hasDistroless := findLine(lines, "gcr.io/distroless/")
	if !hasDistroless {
		t.Error("Dockerfile missing distroless runtime stage")
	}
}

// TestDockerfileNoObsoleteGoVersion is a regression test checking that the old
// golang base image versions (1.22, 1.23) no longer appear in the Dockerfile.
func TestDockerfileNoObsoleteGoVersion(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, "Dockerfile"))

	obsoleteImages := []string{"golang:1.22", "golang:1.23"}
	for _, line := range lines {
		for _, old := range obsoleteImages {
			if strings.Contains(line, old) {
				t.Errorf("Dockerfile still references obsolete image %q in line: %q", old, strings.TrimSpace(line))
			}
		}
	}
}

// ---- Cross-file consistency tests ------------------------------------------

// TestGoVersionConsistency verifies that the Go version in go.yml and the
// Dockerfile build stage are identical, preventing drift between CI and the
// build container.
func TestGoVersionConsistency(t *testing.T) {
	root := repoRoot(t)

	workflowLines := readLines(t, filepath.Join(root, ".github", "workflows", "go.yml"))
	dockerfileLines := readLines(t, filepath.Join(root, "Dockerfile"))

	workflowLine, ok := findLine(workflowLines, "go-version:")
	if !ok {
		t.Fatal("go-version field not found in go.yml")
	}
	dockerLine, ok := findLine(dockerfileLines, "FROM golang:")
	if !ok {
		t.Fatal("FROM golang: not found in Dockerfile")
	}

	workflowVersion := extractGoVersion(workflowLine)
	dockerVersion := extractDockerGoVersion(dockerLine)

	if workflowVersion == "" {
		t.Fatalf("could not parse Go version from go.yml line: %q", workflowLine)
	}
	if dockerVersion == "" {
		t.Fatalf("could not parse Go version from Dockerfile line: %q", dockerLine)
	}
	if workflowVersion != dockerVersion {
		t.Errorf("Go version mismatch: go.yml uses %q but Dockerfile uses %q", workflowVersion, dockerVersion)
	}
}

// TestGoModVersionConsistency verifies that go.mod's minimum Go version is
// consistent with the Go version used in CI and Docker.
func TestGoModVersionConsistency(t *testing.T) {
	root := repoRoot(t)
	lines := readLines(t, filepath.Join(root, "go.mod"))

	goLine, ok := findLine(lines, "\ngo ")
	if !ok {
		// findLine searches with Contains, so try a simpler approach
		for _, l := range lines {
			trimmed := strings.TrimSpace(l)
			if strings.HasPrefix(trimmed, "go ") {
				goLine = trimmed
				ok = true
				break
			}
		}
	}
	if !ok {
		t.Fatal("'go' directive not found in go.mod")
	}

	// go.mod line looks like: "go 1.25.0"
	parts := strings.Fields(strings.TrimSpace(goLine))
	if len(parts) < 2 {
		t.Fatalf("unexpected go.mod 'go' directive format: %q", goLine)
	}
	modVersion := parts[1] // e.g. "1.25.0"

	// Strip patch version for comparison with workflow/Docker (which use "1.25")
	major2 := strings.Join(strings.SplitN(modVersion, ".", 3)[:2], ".")

	if major2 != expectedGoVersion {
		t.Errorf("go.mod go directive = %q (major.minor = %q); want %q to match go.yml and Dockerfile", modVersion, major2, expectedGoVersion)
	}
}

// ---- helper functions ------------------------------------------------------

// extractGoVersion parses a go.yml line like `        go-version: '1.25'` and
// returns "1.25".
func extractGoVersion(line string) string {
	// Find the value after "go-version:"
	idx := strings.Index(line, "go-version:")
	if idx < 0 {
		return ""
	}
	val := strings.TrimSpace(line[idx+len("go-version:"):])
	val = strings.Trim(val, `'"`)
	return val
}

// extractDockerGoVersion parses a Dockerfile line like `FROM golang:1.25 as build-env`
// and returns "1.25".
func extractDockerGoVersion(line string) string {
	// Line looks like: FROM golang:1.25 as build-env
	line = strings.TrimSpace(line)
	fields := strings.Fields(line)
	for _, f := range fields {
		if strings.HasPrefix(f, "golang:") {
			return strings.TrimPrefix(f, "golang:")
		}
	}
	return ""
}
