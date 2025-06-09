MOD_NAME := github.com/opensraph/template.go

# Git variables
GIT_COMMIT    = $(shell git rev-parse HEAD)
GIT_TAG       = $(shell git describe --tags --always --match='v*')
GIT_DIRTY     = $(shell test -n "`git status --porcelain`" && echo "dirty" || echo "clean")
GIT_REPO_URL  = $(shell git remote get-url origin | sed -e 's|git@\(.*\):\(.*\)\.git|https://\1/\2|g')

# Go variables
GO        ?= go
GOOS      := $(shell $(GO) env GOOS)
GOARCH    := $(shell $(GO) env GOARCH)
GOHOST    := GOOS=$(GOOS) GOARCH=$(GOARCH) $(GO)
GOVERSION := $(shell $(GO) version | cut -d ' ' -f 3 | sed 's/go//')
GOPATH    := $(shell $(GO) env GOPATH)

# Build variables
VERSION   ?= $(GIT_TAG)
BUILD_TIME = $(shell date -u +'%Y-%m-%d_%H:%M:%S')
BINARY_NAME = $(shell basename $(MOD_NAME))

# Improved LDFLAGS with more build info
LDFLAGS ?= "-s -w \
	-X ${MOD_NAME}/version.Version=$(VERSION)"

# Colors for output
RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
BLUE   := \033[34m
RESET  := \033[0m

.DEFAULT_GOAL := help

###############
##@ Initial

.PHONY: init
init: ## Initialize development environment
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(BLUE)Installing development tools...$(RESET)"
	$(GO) install github.com/goreleaser/goreleaser@latest
	$(GO) install github.com/air-verse/air@latest
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin
	@echo "$(GREEN)Development environment initialized!$(RESET)"

.PHONY: deps
deps: ## Download and tidy dependencies
	@ $(MAKE) --no-print-directory log-$@
	$(GO) mod download
	$(GO) mod tidy
	$(GO) mod verify

.PHONY: rename
rename: ## Rename Go module (interactive)
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(YELLOW)Current module: $(MOD_NAME)$(RESET)" \
		&& echo "Enter new go module name:" \
		&& read new_module_name \
		&& echo "New module name: '$$new_module_name'" \
		&& echo -n "Are you sure? [y/N] " \
		&& read ans && [ $${ans:-N} = y ] \
		&& echo "$(BLUE)Updating module name...$(RESET)" \
		&& find . -type f -not -path '*/\.git*' -exec sed -i "s|${MOD_NAME}|$$new_module_name|g" {} \; \
		&& echo "$(GREEN)Module renamed successfully!$(RESET)" \
		&& git add . && git commit -m "rename module to '$$new_module_name'"

###############
##@ Development

.PHONY: dev
dev: ## Run development server with hot reload
	@ $(MAKE) --no-print-directory log-$@
	@if command -v air >/dev/null 2>&1; then \
		air; \
	else \
		echo "$(YELLOW)Air not found, running with go run...$(RESET)"; \
		CGO_ENABLED=0 $(GOHOST) run -ldflags=$(LDFLAGS) ./...; \
	fi

.PHONY: run
run: ## Run the application
	@ $(MAKE) --no-print-directory log-$@
	CGO_ENABLED=0 $(GOHOST) run -ldflags=$(LDFLAGS) ./...

.PHONY: watch
watch: ## Watch for file changes and run tests
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(BLUE)Watching for changes...$(RESET)"
	@while true; do \
		find . -name "*.go" | entr -d make test; \
	done

.PHONY: clean
clean: ## Clean workspace and build artifacts
	@ $(MAKE) --no-print-directory log-$@
	$(GO) clean -cache -testcache -modcache
	rm -rf bin/ dist/ coverage.out coverage.html
	@echo "$(GREEN)Workspace cleaned!$(RESET)"

.PHONY: check
check: deps test lint ## Run all checks (deps, tests, linters)

.PHONY: test
test: ## Run tests with coverage
	@ $(MAKE) --no-print-directory log-$@
	$(GO) test -race -coverprofile=coverage.out -covermode=atomic ./...
	$(GO) tool cover -func=coverage.out
	@echo "$(GREEN)Tests completed!$(RESET)"

.PHONY: test-verbose
test-verbose: ## Run tests with verbose output
	@ $(MAKE) --no-print-directory log-$@
	$(GO) test -v -race -coverprofile=coverage.out -covermode=atomic ./...

.PHONY: coverage
coverage: test ## Generate and open coverage report
	@ $(MAKE) --no-print-directory log-$@
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)Coverage report generated: coverage.html$(RESET)"

.PHONY: bench
bench: ## Run benchmarks
	@ $(MAKE) --no-print-directory log-$@
	$(GO) test -bench=. -benchmem ./...

.PHONY: lint
lint: ## Run golangci-lint
	@ $(MAKE) --no-print-directory log-$@
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run --timeout=5m; \
	else \
		echo "$(RED)golangci-lint not found. Run 'make init' first.$(RESET)"; \
		exit 1; \
	fi

.PHONY: fmt
fmt: ## Format code
	@ $(MAKE) --no-print-directory log-$@
	$(GO) fmt ./...
	@if command -v goimports >/dev/null 2>&1; then \
		goimports -w .; \
	fi

.PHONY: vet
vet: ## Run go vet
	@ $(MAKE) --no-print-directory log-$@
	$(GO) vet ./...

#########
##@ Build

.PHONY: build
build: ## Build binary for current platform
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(BLUE)Building $(BINARY_NAME)...$(RESET)"
	mkdir -p bin
	CGO_ENABLED=0 $(GOHOST) build -ldflags=$(LDFLAGS) -o bin/$(BINARY_NAME) ./...
	@echo "$(GREEN)Build completed: bin/$(BINARY_NAME)$(RESET)"

.PHONY: build-all
build-all: ## Build for all platforms
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(BLUE)Building for all platforms...$(RESET)"
	mkdir -p bin
	@for os in linux darwin windows; do \
		for arch in amd64 arm64; do \
			echo "Building $$os/$$arch..."; \
			GOOS=$$os GOARCH=$$arch CGO_ENABLED=0 $(GO) build \
				-ldflags=$(LDFLAGS) \
				-o bin/$(BINARY_NAME)-$$os-$$arch \
				./...; \
		done; \
	done
	@echo "$(GREEN)Multi-platform build completed!$(RESET)"

.PHONY: install
install: ## Install binary to GOPATH/bin
	@ $(MAKE) --no-print-directory log-$@
	CGO_ENABLED=0 $(GO) install -ldflags=$(LDFLAGS) ./...

.PHONY: release
release: ## Create release with goreleaser
	@ $(MAKE) --no-print-directory log-$@
	@if command -v goreleaser >/dev/null 2>&1; then \
		goreleaser release --clean; \
	else \
		echo "$(RED)goreleaser not found. Run 'make init' first.$(RESET)"; \
		exit 1; \
	fi

########
##@ Help
.PHONY: info
info: ## Display build information
	@ $(MAKE) --no-print-directory log-$@
	@echo "$(BLUE)Build Information:$(RESET)"
	@echo "Module Name:        ${MOD_NAME}"
	@echo "Binary Name:        ${BINARY_NAME}"
	@echo "Version:            ${VERSION}"
	@echo "Build Time:         ${BUILD_TIME}"
	@echo ""
	@echo "$(BLUE)Git Information:$(RESET)"
	@echo "Git Tag:            ${GIT_TAG}"
	@echo "Git Commit:         ${GIT_COMMIT}"
	@echo "Git Tree State:     ${GIT_DIRTY}"
	@echo "Git Repository:     ${GIT_REPO_URL}"
	@echo ""
	@echo "$(BLUE)Go Information:$(RESET)"
	@echo "Go Version:         ${GOVERSION}"
	@echo "GOOS:               ${GOOS}"
	@echo "GOARCH:             ${GOARCH}"
	@echo "GOPATH:             ${GOPATH}"

.PHONY: help
help: ## Display this help message
	@awk -v "col=$(BLUE)" -v "nocol=$(RESET)" ' \
		BEGIN { FS = ":.*##" ; printf "Usage:\n  make %s<target>%s\n", col, nocol } \
		/^[a-zA-Z_-]+:.*?##/ { printf "  %s%-15s%s %s\n", col, $$1, nocol, $$2 } \
		/^##@/ { printf "\n%s%s%s\n", "$(YELLOW)", substr($$0, 5), "$(RESET)" }' \
		$(MAKEFILE_LIST)

# Internal target for logging
log-%:
	@grep -h -E '^$*:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN { FS = ":.*?## " }; { printf "$(GREEN)==> %s$(RESET)\n", $$2}'
