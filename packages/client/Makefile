NAME=nixstasis
BIN_DIR=bin
BUILD_ROOT=build/root-dir
INSTALL_DIR=$(BUILD_ROOT)/usr/bin
CMD_DIR=./cmd/nixstasis
GOLANGCI_VERSION=v2.8.0
GOBIN := $(shell go env GOPATH)/bin

export GOEXPERIMENT=jsonv2

# Tool Binaries
GOLANGCI_LINT := $(GOBIN)/golangci-lint
GOFUMPT := $(GOBIN)/gofumpt
GOIMPORTS := $(GOBIN)/goimports

.PHONY: all build test lint clean help fmt mod check install-tools e2e-scaffold
.PHONY: check-golangci-version

all: clean check install ## Run all checks and install the binary

build: ## Build the binary locally (for dev)
	@mkdir -p $(BIN_DIR)
	@echo "Building $(NAME)..."
	go build -o $(BIN_DIR)/$(NAME) $(CMD_DIR)

install: build ## Build and install the binary to BUILD_ROOT
	@echo "Installing $(NAME)..."
	install -D $(BIN_DIR)/$(NAME) $(INSTALL_DIR)/$(NAME)

fmt: $(GOFUMPT) $(GOIMPORTS) ## Format code with gofumpt and goimports
	@echo "Formatting code..."
	@find . -type f -name '*.go' -not -path './tmp/e2e/go-cache/*' -print0 | xargs -0 $(GOFUMPT) -l -w
	@find . -type f -name '*.go' -not -path './tmp/e2e/go-cache/*' -print0 | xargs -0 $(GOIMPORTS) -w -local github.com/RobertDeRose/sfero-nixstasis

lint: $(GOLANGCI_LINT) ## Run golangci-lint
	@echo "Running golangci-lint..."
	@$(GOLANGCI_LINT) run --fix

test: ## Run tests with race detector and coverage
	@echo "Running tests..."
	@go test -v -race -coverprofile=coverage.out ./...
	@go tool cover -func=coverage.out

mod: ## Verify and tidy dependencies
	@echo "Tidying modules..."
	@go mod tidy
	@go mod verify

check: fmt mod lint test ## Run all formatting, linting, and tests
	@echo "✓ All checks passed!"

# Tool Installations
# 1. This target always runs because it is .PHONY
check-golangci-version:
	@if [ -x $(GOLANGCI_LINT) ]; then \
		VERSION_OUTPUT=$$($(GOLANGCI_LINT) version); \
		INSTALLED_VER=$$(printf '%s\n' "$$VERSION_OUTPUT" | awk '{print $$4}'); \
		INSTALLED_GO=$$(printf '%s\n' "$$VERSION_OUTPUT" | awk '{print $$8}'); \
		CURRENT_GO=$$(go env GOVERSION); \
		if [ "v$$INSTALLED_VER" != "$(GOLANGCI_VERSION)" ] || [ "$$INSTALLED_GO" != "$$CURRENT_GO" ]; then \
			echo "golangci-lint mismatch: expected $(GOLANGCI_VERSION) built with $$CURRENT_GO, got $$INSTALLED_VER built with $$INSTALLED_GO. Reinstalling..."; \
			rm -f $(GOLANGCI_LINT); \
		fi; \
	fi

# 2. The binary target now depends on the version check
$(GOLANGCI_LINT): check-golangci-version
	@if [ ! -f $(GOLANGCI_LINT) ]; then \
		echo "Installing golangci-lint $(GOLANGCI_VERSION) with local Go toolchain..."; \
		GOBIN=$(GOBIN) go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_VERSION); \
	fi

$(GOFUMPT):
	@echo "Installing gofumpt..."
	@go install mvdan.cc/gofumpt@latest

$(GOIMPORTS):
	@echo "Installing goimports..."
	@go install golang.org/x/tools/cmd/goimports@latest

install-tools: $(GOLANGCI_LINT) $(GOFUMPT) $(GOIMPORTS) ## Install all required development tools

clean: ## Remove build artifacts
	@echo "Cleaning..."
	@rm -rf $(BIN_DIR)
	@rm -f coverage.out

run_mock_server: ## Run a mock api server for testing
	@echo "Starting mock server..."
	@go run ./scripts/mock_api -log=stderr

e2e-scaffold: ## Generate E2E journey scaffold (requires ID; optional SUITE, DESCRIPTION, STEPS)
	@if [ -z "$(ID)" ]; then \
		echo "Usage: make e2e-scaffold ID=<journey_id> [SUITE=runtime] [DESCRIPTION='...'] [STEPS=action:expect,...]"; \
		exit 1; \
	fi
	@scripts/e2e/scaffold --id "$(ID)" \
		$(if $(SUITE),--suite "$(SUITE)",) \
		$(if $(DESCRIPTION),--description "$(DESCRIPTION)",) \
		$(if $(STEPS),--steps "$(STEPS)",) \
		$(if $(FORCE),--force,) \
		$(if $(DRY_RUN),--dry-run,)

help:
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
