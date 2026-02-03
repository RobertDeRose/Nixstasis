# Go 1.25 Best Practices Guide

**Last Updated:** February 2026
**Go Version:** 1.25.6 (latest stable)

This guide outlines best practices for developing robust, maintainable, and performant Go applications using Go 1.25. It incorporates the latest features and improvements introduced in this release.

---

## Table of Contents

1. [What's New in Go 1.25](#whats-new-in-go-125)
2. [Project Structure](#project-structure)
3. [Language Features & Patterns](#language-features--patterns)
4. [Concurrency Best Practices](#concurrency-best-practices)
5. [Error Handling](#error-handling)
6. [Performance Optimization](#performance-optimization)
7. [Testing](#testing)
8. [Containerization & Deployment](#containerization--deployment)
9. [Code Quality & Tooling](#code-quality--tooling)
10. [Standard Library Updates](#standard-library-updates)

---

## What's New in Go 1.25

### Major Features

#### 1. Container-Aware GOMAXPROCS

Go 1.25 automatically adjusts `GOMAXPROCS` based on container CPU limits, improving performance in containerized environments.

**Key Changes:**

- On Linux, the runtime considers cgroup CPU bandwidth limits
- `GOMAXPROCS` defaults to the lower of: logical CPUs or cgroup CPU limit
- The runtime periodically updates `GOMAXPROCS` if CPU availability changes
- Automatic behavior only applies if `go.mod` specifies Go 1.25+

**Best Practice:**

```go
// No manual GOMAXPROCS setting needed in containers
// The runtime handles it automatically

// To disable automatic behavior if needed:
// GODEBUG=containermaxprocs=0 go run main.go
// GODEBUG=updatemaxprocs=0 go run main.go
```

#### 2. Experimental JSON v2 Package

A new high-performance JSON implementation with improved API and performance.

**Enable with:**

```bash
GOEXPERIMENT=jsonv2 go build
```

**Best Practice:**

```go
import (
    "encoding/json/v2"
    "encoding/json/v2/jsontext"
)

type Config struct {
    Name    string    `json:"name"`
    Timeout int       `json:"timeout"`
    Created time.Time `json:"created,format:DateOnly"`
    Extra   map[string]any `json:",unknown"` // Capture unknown fields
}

// Stream marshaling without intermediate buffers
var buf bytes.Buffer
if err := json.MarshalWrite(&buf, config); err != nil {
    return err
}

// Pretty printing with indent
data, err := json.Marshal(config, jsontext.WithIndent("  "))
```

**Benefits:**

- Faster decoding performance
- Better control over marshaling/unmarshaling
- Streaming support via `MarshalWrite` and `UnmarshalRead`
- Unknown field handling with `,unknown` tag
- Field inlining with `,inline` tag
- Custom date formatting

#### 3. Testing Concurrent Code with `testing/synctest`

Graduated from experimental to stable, this package enables deterministic testing of concurrent code.

**Best Practice:**

```go
import (
    "testing"
    "testing/synctest"
    "time"
)

func TestConcurrentOperation(t *testing.T) {
    synctest.Run(func() {
        result := make(chan int)

        go func() {
            time.Sleep(10 * time.Second) // Virtualized time
            result <- 42
        }()

        // Waits for all goroutines to block
        synctest.Wait()

        select {
        case v := <-result:
            if v != 42 {
                t.Errorf("expected 42, got %d", v)
            }
        default:
            t.Error("expected result")
        }
    })
}
```

**Benefits:**

- Deterministic concurrent tests
- Virtualized time (no real waiting)
- Instant time progression when all goroutines block
- Easier to test race conditions and deadlocks

#### 4. Experimental Green Tea Garbage Collector

Optimized for high-core systems and programs that create many small objects.

**Enable with:**

```bash
GOEXPERIMENT=greenteagc go build
```

**Best Practice:**

- Test in staging environments first
- Monitor GC pause times and memory usage
- Particularly beneficial for:
  - High-core count systems (8+ cores)
  - Non-uniform memory architectures
  - Applications creating many small objects
  - Benchmarks show 10-40% GC overhead reduction in some workloads

#### 5. DWARF v5 Debug Information

Smaller binaries and faster linking with modern debug information format.

**Default behavior:** DWARF v5 is enabled by default

**Disable if needed:**

```bash
GOEXPERIMENT=nodwarf5 go build
```

**Benefits:**

- Smaller binary sizes
- Faster linking, especially for large binaries
- Better debugger compatibility with modern tools

#### 6. Flight Recorder for Tracing

Lightweight in-memory ring buffer for capturing execution traces.

**Best Practice:**

```go
import (
    "os"
    "runtime/trace"
)

func main() {
    rec, err := trace.NewFlightRecorder(trace.FlightRecorderConfig{})
    if err != nil {
        panic(err)
    }
    defer rec.Close()

    // Run your application logic
    runApplication()

    // On failure or interesting event, capture trace
    if criticalEvent {
        f, _ := os.Create("trace.out")
        rec.WriteTo(f, "")
    }
}
```

**Benefits:**

- Low overhead (ring buffer in memory)
- Capture only relevant events
- Smaller trace files
- On-demand trace snapshots

#### 7. Enhanced Nil Pointer Checking

Compiler now correctly panics on nil pointer dereferences (fixes bug from Go 1.21-1.24).

**Migration Required:**

```go
// INCORRECT - will now panic as expected
f, err := os.Open("nonExistentFile")
name := f.Name() // Panic! f is nil
if err != nil {
    return
}

// CORRECT - check error first
f, err := os.Open("nonExistentFile")
if err != nil {
    return err
}
name := f.Name() // Safe
```

**Best Practice:**

- Always check errors immediately after error-producing statements
- Never use potentially nil values before checking errors

#### 8. Cross-Origin Protection for HTTP

New `http.CrossOriginProtection` type implements CSRF protection.

**Best Practice:**

```go
import "net/http"

func setupServer() {
    // Enable CSRF protection
    corsProtection := &http.CrossOriginProtection{
        ExtraOrigins: []string{"https://trusted.example.com"},
    }

    mux := http.NewServeMux()
    mux.HandleFunc("/api/data", handleData)

    // Wrap handler with CSRF protection
    handler := corsProtection.Handler(mux)
    http.ListenAndServe(":8080", handler)
}
```

---

## Project Structure

### Recommended Directory Layout

```
myproject/
├── cmd/
│   └── myapp/
│       └── main.go          # Application entry point
├── internal/
│   ├── api/                 # HTTP handlers, API logic
│   ├── database/            # Database access layer
│   ├── models/              # Domain models
│   └── service/             # Business logic
├── pkg/
│   └── utilities/           # Public reusable packages
├── configs/
│   └── config.yaml          # Configuration files
├── scripts/
│   └── migrate.sh           # Build/deployment scripts
├── test/
│   └── integration/         # Integration tests
├── docs/
│   └── api.md              # Documentation
├── go.mod
├── go.sum
└── README.md
```

### Directory Guidelines

**`/cmd`** - Main applications

- Each application should match the executable name
- Keep application code minimal
- Import from `/internal` and `/pkg`

**`/internal`** - Private application code

- Code you don't want others importing
- Enforced by the Go compiler (Go 1.4+)
- Use for application-specific logic

**`/pkg`** - Public library code

- Code that's safe for others to import
- Use sparingly; prefer `/internal` by default
- Only export what truly needs to be public

**Avoid:**

- `/src` directory (Java-style, not idiomatic in Go)
- Deeply nested package hierarchies
- Over-packaging (prefer fewer, larger packages)

---

## Language Features & Patterns

### Variable Naming

**Best Practices:**

```go
// Good: Short names for short scopes
for i := 0; i < len(items); i++ {
    // i is clear in this context
}

// Good: Descriptive names for longer scopes
func processUserAuthentication(authenticationRequest *AuthRequest) error {
    // Longer name justified by scope and importance
}

// Bad: Unnecessary verbosity
for userIndex := 0; userIndex < len(users); userIndex++ {
    // Too verbose for simple loop
}

// Good: Single letter for receivers
func (c *Client) Connect() error {
    // c is conventional for Client
}

// Good: Avoid type name in variable name
var users []*User  // Not "userList" or "userSlice"
```

**Guidelines:**

- Distance between declaration and use dictates name length
- Short names (1-2 chars) for loops, receivers, small scopes
- Longer names for package-level declarations and parameters
- Don't include type information in variable names

### Constants

```go
// Good: Describe the value, not the usage
const MaxRetries = 3
const DefaultTimeout = 30 * time.Second

// Bad: Describe usage instead of value
const MaxRetriesForDatabaseConnection = 3
```

### Error Handling

**Line-of-Sight Coding:**

```go
// Good: Success path stays left-aligned
func ProcessData(data []byte) error {
    if len(data) == 0 {
        return ErrEmptyData
    }

    parsed, err := Parse(data)
    if err != nil {
        return fmt.Errorf("parse failed: %w", err)
    }

    validated, err := Validate(parsed)
    if err != nil {
        return fmt.Errorf("validation failed: %w", err)
    }

    return Store(validated)
}

// Bad: Success path indented
func ProcessData(data []byte) error {
    if len(data) != 0 {
        if parsed, err := Parse(data); err == nil {
            if validated, err := Validate(parsed); err == nil {
                return Store(validated)
            } else {
                return err
            }
        } else {
            return err
        }
    }
    return ErrEmptyData
}
```

**Error Wrapping (Go 1.13+):**

```go
import (
    "errors"
    "fmt"
)

// Wrap errors to add context
func ReadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("failed to read config from %s: %w", path, err)
    }

    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("failed to parse config: %w", err)
    }

    return &cfg, nil
}

// Check specific errors
var ErrNotFound = errors.New("resource not found")

func GetUser(id string) (*User, error) {
    // ...
    if !exists {
        return nil, fmt.Errorf("user %s: %w", id, ErrNotFound)
    }
}

// Usage:
user, err := GetUser("123")
if errors.Is(err, ErrNotFound) {
    // Handle not found
}
```

### Dependency Injection

**Avoid Global Variables:**

```go
// Bad: Global database connection
var db *sql.DB

func main() {
    db = openDatabase()
    http.HandleFunc("/users", GetUsers)
}

func GetUsers(w http.ResponseWriter, r *http.Request) {
    rows, err := db.Query("SELECT * FROM users")
    // ...
}

// Good: Dependency injection via struct
type Handlers struct {
    DB *sql.DB
}

func (h *Handlers) GetUsers(w http.ResponseWriter, r *http.Request) {
    rows, err := h.DB.Query("SELECT * FROM users")
    // ...
}

func main() {
    db := openDatabase()
    handlers := &Handlers{DB: db}
    http.HandleFunc("/users", handlers.GetUsers)
}
```

---

## Concurrency Best Practices

### Goroutine Lifecycle Management

**Always ensure goroutines can exit:**

```go
// Good: Context for cancellation
func Worker(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        default:
            // Do work
            doWork()
        }
    }
}

func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    go Worker(ctx)

    // Application logic
    // cancel() will be called on exit
}
```

**WaitGroup Pattern:**

```go
import "sync"

func ProcessItems(items []Item) error {
    var wg sync.WaitGroup
    errChan := make(chan error, len(items))

    for _, item := range items {
        wg.Add(1)
        go func(item Item) {
            defer wg.Done()
            if err := process(item); err != nil {
                errChan <- err
            }
        }(item)
    }

    // Wait for all goroutines
    wg.Wait()
    close(errChan)

    // Collect errors
    for err := range errChan {
        if err != nil {
            return err
        }
    }
    return nil
}
```

**New in Go 1.25: WaitGroup.Go Method:**

```go
import "sync"

func ProcessItems(items []Item) {
    var wg sync.WaitGroup

    for _, item := range items {
        // WaitGroup.Go automatically handles Add(1) and Done()
        wg.Go(func() {
            process(item)
        })
    }

    wg.Wait()
}
```

### Channel Best Practices

**Buffered vs Unbuffered:**

```go
// Unbuffered: Synchronous communication
done := make(chan struct{})

// Buffered: Asynchronous up to capacity
results := make(chan Result, 10)

// Close channels when done sending
go func() {
    for _, item := range items {
        results <- process(item)
    }
    close(results) // Sender closes
}()

// Range over closed channel
for result := range results {
    handle(result)
}
```

**Worker Pool Pattern:**

```go
func WorkerPool(ctx context.Context, jobs <-chan Job, workers int) {
    var wg sync.WaitGroup

    for i := 0; i < workers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for {
                select {
                case <-ctx.Done():
                    return
                case job, ok := <-jobs:
                    if !ok {
                        return
                    }
                    processJob(job)
                }
            }
        }()
    }

    wg.Wait()
}
```

### Testing Concurrent Code (Go 1.25)

**Use `testing/synctest` for deterministic tests:**

```go
import (
    "testing"
    "testing/synctest"
    "time"
)

func TestConcurrentCache(t *testing.T) {
    synctest.Run(func() {
        cache := NewCache()

        // Spawn multiple goroutines
        for i := 0; i < 10; i++ {
            go func(id int) {
                cache.Set(id, id*2)
            }(i)
        }

        // Wait for all goroutines to complete or block
        synctest.Wait()

        // Verify results
        for i := 0; i < 10; i++ {
            val, ok := cache.Get(i)
            if !ok || val != i*2 {
                t.Errorf("cache[%d] = %v, want %v", i, val, i*2)
            }
        }
    })
}
```

### Race Condition Prevention

**Use the race detector:**

```bash
# During testing
go test -race ./...

# During development
go run -race main.go

# In builds (performance cost)
go build -race
```

**Proper synchronization:**

```go
import "sync"

// Good: Mutex for shared state
type SafeCounter struct {
    mu    sync.Mutex
    count map[string]int
}

func (c *SafeCounter) Inc(key string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count[key]++
}

// Good: Use sync.Map for concurrent maps
var cache sync.Map

func GetOrCreate(key string) *Value {
    if v, ok := cache.Load(key); ok {
        return v.(*Value)
    }

    newVal := createValue(key)
    actual, _ := cache.LoadOrStore(key, newVal)
    return actual.(*Value)
}

// Good: Use atomic operations for counters
import "sync/atomic"

var requestCount atomic.Int64

func handleRequest() {
    requestCount.Add(1)
    // Process request
}
```

---

## Error Handling

### Error Types

**Sentinel Errors:**

```go
import "errors"

var (
    ErrNotFound    = errors.New("resource not found")
    ErrUnauthorized = errors.New("unauthorized access")
    ErrInvalidInput = errors.New("invalid input")
)

// Usage
func GetResource(id string) (*Resource, error) {
    if !exists(id) {
        return nil, ErrNotFound
    }
    return load(id), nil
}

// Check
resource, err := GetResource("123")
if errors.Is(err, ErrNotFound) {
    // Handle not found
}
```

**Custom Error Types:**

```go
type ValidationError struct {
    Field string
    Value any
    Msg   string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed for %s: %s", e.Field, e.Msg)
}

// Usage
func Validate(user *User) error {
    if user.Email == "" {
        return &ValidationError{
            Field: "Email",
            Value: user.Email,
            Msg:   "email is required",
        }
    }
    return nil
}

// Check
var valErr *ValidationError
if errors.As(err, &valErr) {
    fmt.Printf("Validation failed for field: %s\n", valErr.Field)
}
```

### Error Wrapping Best Practices

```go
// Add context when wrapping
func ProcessFile(path string) error {
    data, err := os.ReadFile(path)
    if err != nil {
        return fmt.Errorf("failed to read file %s: %w", path, err)
    }

    result, err := parse(data)
    if err != nil {
        return fmt.Errorf("failed to parse file %s: %w", path, err)
    }

    return save(result)
}

// Unwrap to check original error
err := ProcessFile("config.json")
if errors.Is(err, os.ErrNotExist) {
    // Handle file not found
}
```

### Panic and Recover

**Use panic only for truly exceptional situations:**

```go
// Good: Panic for programmer errors
func MustConnect(dsn string) *sql.DB {
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        panic(fmt.Sprintf("failed to connect to database: %v", err))
    }
    return db
}

// Good: Recover in servers to prevent crashes
func handler(w http.ResponseWriter, r *http.Request) {
    defer func() {
        if err := recover(); err != nil {
            log.Printf("panic recovered: %v\n%s", err, debug.Stack())
            http.Error(w, "Internal Server Error", 500)
        }
    }()

    // Handler logic that might panic
    processRequest(w, r)
}
```

---

## Performance Optimization

### Profile-Guided Optimization (PGO)

**Stable in Go 1.25:**

```bash
# 1. Build and run with profiling
go build -o myapp
./myapp -cpuprofile=cpu.pprof

# 2. Rebuild with PGO
go build -pgo=cpu.pprof -o myapp-optimized

# Typical improvements: 2-7% in real-world applications
```

### Memory Optimization

**Stack vs Heap Allocations:**

```go
// Check escape analysis
go build -gcflags="-m" main.go

// Good: Stack allocation (Go 1.25 improved)
func processSmallData() []byte {
    data := make([]byte, 100) // May be stack-allocated
    // Use data
    return data
}

// Avoid unnecessary heap allocations
// Bad
func concat(strs ...string) string {
    var result string
    for _, s := range strs {
        result += s // Multiple allocations
    }
    return result
}

// Good
import "strings"

func concat(strs ...string) string {
    var b strings.Builder
    for _, s := range strs {
        b.WriteString(s)
    }
    return b.String()
}
```

**Sync.Pool for Temporary Objects:**

```go
import "sync"

var bufferPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func ProcessData(data []byte) ([]byte, error) {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer bufferPool.Put(buf)

    buf.Reset()
    // Use buffer
    buf.Write(data)

    return buf.Bytes(), nil
}
```

### Garbage Collector Tuning

**Go 1.25 GC Improvements:**

```bash
# Monitor GC behavior
GODEBUG=gctrace=1 go run main.go

# Try experimental Green Tea GC
GOEXPERIMENT=greenteagc go build

# Tune GC target percentage (default 100)
GOGC=200 go run main.go  # Less frequent GC
GOGC=50 go run main.go   # More frequent GC
```

**Memory Limit (Go 1.19+):**

```bash
# Set soft memory limit
GOMEMLIMIT=2GiB go run main.go
```

### String Operations

```go
// Efficient string building
import "strings"

func buildQuery(fields []string) string {
    var b strings.Builder
    b.WriteString("SELECT ")
    b.WriteString(strings.Join(fields, ", "))
    b.WriteString(" FROM users")
    return b.String()
}

// Use []byte for mutable strings
func processText(s string) string {
    b := []byte(s)
    // Modify in place
    for i := range b {
        b[i] = toUpper(b[i])
    }
    return string(b)
}
```

---

## Testing

### Table-Driven Tests

```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name string
        a, b int
        want int
    }{
        {"positive numbers", 2, 3, 5},
        {"negative numbers", -2, -3, -5},
        {"mixed", 5, -3, 2},
        {"zeros", 0, 0, 0},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := Add(tt.a, tt.b)
            if got != tt.want {
                t.Errorf("Add(%d, %d) = %d, want %d",
                    tt.a, tt.b, got, tt.want)
            }
        })
    }
}
```

### Subtests and Parallel Testing

```go
func TestAPI(t *testing.T) {
    t.Run("GET", func(t *testing.T) {
        t.Parallel() // Run in parallel with other subtests
        // Test GET endpoint
    })

    t.Run("POST", func(t *testing.T) {
        t.Parallel()
        // Test POST endpoint
    })
}
```

### Test Helpers

```go
func TestUserCreation(t *testing.T) {
    t.Helper() // Mark as helper

    db := setupTestDB(t)
    defer db.Close()

    // Test logic
}

func setupTestDB(t *testing.T) *sql.DB {
    t.Helper() // Mark as helper

    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("failed to open test database: %v", err)
    }
    return db
}
```

### Benchmarking

```go
func BenchmarkProcessing(b *testing.B) {
    data := generateTestData()

    b.ResetTimer() // Reset timer after setup

    for i := 0; i < b.N; i++ {
        process(data)
    }
}

// Run benchmarks
// go test -bench=. -benchmem
```

### Concurrent Testing with synctest (Go 1.25)

```go
import "testing/synctest"

func TestRateLimiter(t *testing.T) {
    synctest.Run(func() {
        limiter := NewRateLimiter(10, time.Second)

        // Simulate concurrent requests
        for i := 0; i < 20; i++ {
            go func() {
                limiter.Wait()
            }()
        }

        synctest.Wait()

        if limiter.allowed != 10 {
            t.Errorf("expected 10 allowed, got %d", limiter.allowed)
        }
    })
}
```

---

## Containerization & Deployment

### Container Best Practices (Go 1.25)

**Multi-stage Dockerfile:**

```dockerfile
# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /myapp ./cmd/myapp

# Final stage
FROM scratch

# Copy CA certificates for HTTPS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /myapp /myapp

# Expose port
EXPOSE 8080

# Run
ENTRYPOINT ["/myapp"]
```

**Leverage Go 1.25 Container-Aware GOMAXPROCS:**

```yaml
# kubernetes.yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: myapp:latest
    resources:
      limits:
        cpu: "2"        # Go 1.25 automatically adjusts GOMAXPROCS
        memory: "2Gi"
      requests:
        cpu: "1"
        memory: "1Gi"
```

**No manual GOMAXPROCS configuration needed!**

### Health Checks

```go
func healthHandler(w http.ResponseWriter, r *http.Request) {
    // Check dependencies
    if err := db.Ping(); err != nil {
        w.WriteHeader(http.StatusServiceUnavailable)
        json.NewEncoder(w).Encode(map[string]string{
            "status": "unhealthy",
            "error":  err.Error(),
        })
        return
    }

    w.WriteHeader(http.StatusOK)
    json.NewEncoder(w).Encode(map[string]string{
        "status": "healthy",
    })
}
```

### Graceful Shutdown

```go
func main() {
    srv := &http.Server{
        Addr:    ":8080",
        Handler: router,
    }

    // Start server
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()

    // Wait for interrupt signal
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    log.Println("Shutting down server...")

    // Graceful shutdown with timeout
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatal("Server forced to shutdown:", err)
    }

    log.Println("Server exiting")
}
```

---

## Code Quality & Tooling

### Essential Tools

```bash
# Format code
go fmt ./...
# or
gofmt -w .

# Imports management
go install golang.org/x/tools/cmd/goimports@latest
goimports -w .

# Linting
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
golangci-lint run

# Static analysis
go vet ./...

# Race detection
go test -race ./...

# Dependency management
go mod tidy
go mod verify

# Security scanning
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```

### golangci-lint Configuration

```yaml
# .golangci.yml
linters:
  enable:
    - gofmt
    - govet
    - errcheck
    - staticcheck
    - ineffassign
    - gosec
    - goconst
    - misspell
    - unparam
    - unused

linters-settings:
  govet:
    check-shadowing: true
  gofmt:
    simplify: true

run:
  timeout: 5m
  tests: true
```

### Code Organization

**Keep packages focused:**

```go
// Good: Single responsibility
package user

type Service struct {
    repo Repository
}

func (s *Service) Create(ctx context.Context, u *User) error {
    return s.repo.Save(ctx, u)
}

// Bad: Too many responsibilities
package app

type Service struct {
    userRepo UserRepository
    authService AuthService
    emailService EmailService
    logger Logger
    cache Cache
}
```

---

## Standard Library Updates

### Notable Go 1.25 Additions

#### os.Root for Filesystem Sandboxing

```go
import "os"

func processUserFiles(userDir string) error {
    // Create sandboxed filesystem root
    root, err := os.OpenRoot(userDir)
    if err != nil {
        return err
    }
    defer root.Close()

    // All operations confined to userDir
    file, err := root.Open("data.txt")
    if err != nil {
        return err
    }
    defer file.Close()

    // Cannot access files outside userDir
    return nil
}
```

#### slog Enhancements

```go
import "log/slog"

// Group attributes for structured logging
logger := slog.Default()

logger.Info("request processed",
    slog.GroupAttrs("request",
        slog.String("method", "GET"),
        slog.String("path", "/api/users"),
        slog.Int("status", 200),
    ),
    slog.Duration("latency", time.Millisecond*150),
)
```

#### reflect.TypeAssert

```go
import "reflect"

// Type assertion with reflection
var val any = 42

if num, ok := reflect.TypeAssert[int](val); ok {
    fmt.Printf("Value is int: %d\n", num)
}
```

---

## Security Best Practices

### Input Validation

```go
import (
    "net/http"
    "regexp"
)

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)

func validateEmail(email string) error {
    if !emailRegex.MatchString(email) {
        return errors.New("invalid email format")
    }
    return nil
}
```

### SQL Injection Prevention

```go
// Always use parameterized queries
// Bad
query := fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", userName)
rows, err := db.Query(query)

// Good
rows, err := db.Query("SELECT * FROM users WHERE name = ?", userName)
```

### CSRF Protection (Go 1.25)

```go
import "net/http"

func main() {
    corsProtection := &http.CrossOriginProtection{
        ExtraOrigins: []string{"https://app.example.com"},
    }

    mux := http.NewServeMux()
    mux.HandleFunc("POST /api/transfer", handleTransfer)

    // Apply CSRF protection
    http.ListenAndServe(":8080", corsProtection.Handler(mux))
}
```

### Secrets Management

```go
import "os"

// Never hardcode secrets
// Bad
const apiKey = "sk-1234567890abcdef"

// Good: Use environment variables
apiKey := os.Getenv("API_KEY")
if apiKey == "" {
    log.Fatal("API_KEY environment variable required")
}
```

---

## Conclusion

Go 1.25 brings significant improvements for cloud-native development, particularly in container environments. Key takeaways:

1. **Container-Aware Runtime**: Automatic GOMAXPROCS adjustment improves performance in Kubernetes/Docker
2. **Better Testing**: `testing/synctest` makes concurrent code testing deterministic
3. **Performance**: Experimental Green Tea GC and JSON v2 offer substantial performance gains
4. **Security**: Built-in CSRF protection and enhanced nil-pointer checking
5. **Observability**: Flight recorder enables targeted trace capture

**Migration Checklist:**

- [ ] Update `go.mod` to Go 1.25
- [ ] Fix nil pointer dereference errors (check errors before using values)
- [ ] Test in containers to verify GOMAXPROCS behavior
- [ ] Evaluate experimental JSON v2 for performance-critical paths
- [ ] Try Green Tea GC in staging environments
- [ ] Update concurrent tests to use `testing/synctest`
- [ ] Enable CSRF protection for web applications
- [ ] Run `go vet` and address new warnings

**Resources:**

- [Official Go 1.25 Release Notes](https://go.dev/doc/go1.25)
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
- [Go Style Guide (Google)](https://google.github.io/styleguide/go/)

---

**Version:** 1.0.0
**Last Updated:** February 2026
**Go Version:** 1.25.6
