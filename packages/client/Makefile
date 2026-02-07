NAME=nixstasis
BIN_DIR=bin
BUILD_ROOT=build/root-dir
INSTALL_DIR=$(BUILD_ROOT)/usr/bin
CMD_DIR=./cmd/nixstasis
LINTER_VERSION=v2.8.0

export GOEXPERIMENT=jsonv2

.PHONY: all build test lint clean help

all: clean build test

build: ## Build the binary locally (for dev)
	@echo "Building $(NAME)..."
	go build -o $(BIN_DIR)/$(NAME) $(CMD_DIR)

install: bin/nixstasis ## Build and install the binary
	@echo "Installing $(NAME)..."
	install -D $(BIN_DIR)/$(NAME) $(INSTALL_DIR)/$(NAME)

test: ## Run tests
	@echo "Running tests..."
	go test -v ./...

lint: ## Run linter
	@echo "Running linter..."
	 golangci-lint fmt
	 golangci-lint run --fix

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf $(BIN_DIR)/$(NAME)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
