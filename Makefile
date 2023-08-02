
# ! Top ~64 lines are from upstream. Fix later

# GO ?= $(shell command -v go 2> /dev/null)
# BASH ?= $(shell command -v bash 2> /dev/null)

# # Development
# SHIORI_DIR ?= dev-data

# # Testing
# GO_TEST_FLAGS ?= -v -race
# GOTESTFMT_FLAGS ?=

# # Build
# CGO_ENABLED ?= 0
# BUILD_TIME := $(shell date -u +%Y%m%d.%H%M%S)
# BUILD_HASH := $(shell git describe --tags)
# BUILD_TAGS ?= osusergo,netgo
# LDFLAGS += -s -w -X main.version=$(BUILD_HASH) -X main.date=$(BUILD_TIME)

# # Development
# GIN_MODE ?= debug
# SHIORI_DEVELOPMENT ?= true

# ## Cleans up build artifacts
# .PHONY: clean
# clean:
# 	rm -rf dist

# ## Runs the legacy http API for local development
# .PHONY: serve
# serve:
# 	SHIORI_DEVELOPMENT=$(SHIORI_DEVELOPMENT) SHIORI_DIR=$(SHIORI_DIR) go run main.go serve

# ## Runs server for local development
# .PHONY: run-server
# run-server:
# 	GIN_MODE=$(GIN_MODE) SHIORI_DEVELOPMENT=$(SHIORI_DEVELOPMENT) SHIORI_DIR=$(SHIORI_DIR) go run main.go server

# ## Generate swagger docs
# .PHONY: swagger
# swagger:
# 	swag init

# ## Run linter
# .PHONY: lint
# lint:
# 	golangci-lint run

# ## Run unit tests
# .PHONY: unittest
# unittest:
# 	GIN_MODE=$(GIN_MODE) GO_TEST_FLAGS="$(GO_TEST_FLAGS)" GOTESTFMT_FLAGS="$(GOTESTFMT_FLAGS)" $(BASH) -xe ./scripts/test.sh

# ## Build binary
# .PHONY: build
# build: clean
# 	GIN_MODE=$(GIN_MODE) goreleaser build --rm-dist --snapshot

# ## Creates a coverage report
# .PHONY: coverage
# coverage:
# 	$(GO) test $(GO_TEST_FLAGS) -coverprofile=coverage.txt ./...
# 	$(GO) tool cover -html=coverage.txt

.DEFAULT_GOAL		:= help
.ONESHELL:
export SHELL 		:= $(shell which sh)

# silence exported variable stdout
$(VERBOSE).SILENT:

# env variables
export BINARY_NAME				:= shiori
export TLD						:= $(shell git rev-parse --show-toplevel)
export DOCKERFILE				:= $(TLD)/Dockerfile
export DOCKER_BUILDKIT			:= 0
export COMPOSE_DOCKER_CLI_BUILD	:= 0
# export DOCKER_DEFAULT_PLATFORM	:= linux/amd64
export GIT_TAG 					?= $(shell git describe --tags --abbrev=0 --exact-match 2>/dev/null)
export GIT_USER 				:= $(shell git config --get remote.origin.url | awk -F/ '{print $$4}')
export GIT_REPO 				:= $(shell git config --get remote.origin.url | awk -F/ '{print $$NF}' | sed 's/.git//')
export GIT_VERSION 				?= $(shell git describe --tags --always --dirty)
export GIT_HASH 				?= $(shell git rev-parse HEAD)
include $(TLD)/.env

# colors
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
CYAN   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

# GOPATH
ifeq (,$(shell go env GOBIN))
	GOBIN=$(shell go env GOPATH)/bin
else
	GOBIN=$(shell go env GOBIN)
endif

# set version variables for LDFLAGS
DATE_FMT 	:= +'%Y-%m-%dT%H:%M:%SZ'
SOURCE_DATE_EPOCH ?= $(shell git log -1 --pretty=%ct)
ifdef SOURCE_DATE_EPOCH
    BUILD_DATE ?= $(shell date -u -d "@$(SOURCE_DATE_EPOCH)" "$(DATE_FMT)" 2>/dev/null || date -u -r "$(SOURCE_DATE_EPOCH)" "$(DATE_FMT)" 2>/dev/null || date -u "$(DATE_FMT)")
else
    BUILD_DATE ?= $(shell date "$(DATE_FMT)")
endif
GIT_TREESTATE = "clean"
DIFF = $(shell git diff --quiet >/dev/null 2>&1; if [ $$? -eq 1 ]; then echo "1"; fi)
ifeq ($(DIFF), 1)
    GIT_TREESTATE = "dirty"
endif

# set goreleaser variables
PKG = github.com/$(GIT_USER)/$(GIT_REPO)
LDFLAGS = "-X $(PKG).GitVersion=$(GIT_VERSION) -X $(PKG).gitCommit=$(GIT_HASH) -X $(PKG).gitTreeState=$(GIT_TREESTATE) -X $(PKG).buildDate=$(BUILD_DATE)"

# targets
.PHONY: all
all: build run clean test vet release lint release help

build:	## build binary
	@echo "Building ${BINARY_NAME}..."
	GOARCH=amd64 GOOS=darwin go build -o ./dist/${BINARY_NAME}-darwin main.go
	GOARCH=amd64 GOOS=linux go build -o ./dist/${BINARY_NAME}-linux main.go
	GOARCH=amd64 GOOS=windows go build -o ./dist/${BINARY_NAME}-windows main.go

run: build  ## run binary
	@echo "Running ${BINARY_NAME}..."
	./${BINARY_NAME}

clean:  ## clean binary
	@echo "Cleaning..."
	go clean
	rm -rf ./dist/

test:  # test
	@echo "Testing..."
	go test ./...

test_coverage:  # test with coverage
	@echo "Testing with coverage..."
	go test ./... -coverprofile=coverage.out

dep:  ## download dependencies
	@echo "Downloading dependencies..."
	go mod download

vet:  ## vet
	@echo "Vetting..."
	go vet

lint:  ## lint
	@echo "Linting..."
	golangci-lint run --enable-all

validate:  ## validate goreleaser config
	@echo "Validating goreleaser..."
	goreleaser check || exit 1

tag-semver:  ## tag as version
	@echo "Tagging..."
	if [ "$(GIT_TAG)" = 'latest' ] || [ -z "$(GIT_TAG)" ]; then \
		VERSION=$$(cat VERSION); \
		MAJOR=$$(echo $$VERSION | cut -d. -f1); \
		MINOR=$$(echo $$VERSION | cut -d. -f2); \
		PATCH=$$(echo $$VERSION | cut -d. -f3); \
		PATCH=$$(expr $$PATCH + 1); \
		echo "$$MAJOR.$$MINOR.$$PATCH" > VERSION; \
		git tag -a "v$$MAJOR.$$MINOR.$$PATCH" -m "Release v$$MAJOR.$$MINOR.$$PATCH"; \
	else \
		git tag -a $(GIT_TAG) -m "Release $(GIT_TAG)"; \
	fi

docker-login:  ## login to dockerhub
	ret_code=$$(docker info > /dev/null 2>&1; echo $$?); \
	if [ $$ret_code -ne 0 ]; then \
		echo "Logging in to dockerhub..."; \
		docker login -u $(DOCKER_USER) -p $(DOCKER_PASS); \
	else \
		echo "Already logged in to dockerhub"; \
	fi

ghcr-login:  ## login to ghcr
	ret_code=$$(docker info > /dev/null 2>&1; echo $$?); \
	if [ $$ret_code -ne 0 ]; then \
		echo "Logging in to ghcr.io..."; \
		echo $(GITHUB_TOKEN) | docker login ghcr.io -u USERNAME --password-stdin; \
	else \
		echo "Already logged in to ghcr.io"; \
	fi

release-qa:	validate ## release to qa
	@echo "Releasing to qa..."
	export GITHUB_TOKEN=$(GITHUB_TOKEN) && \
	export DOCKER_REG=$(DOCKER_REG) && \
	LDFLAGS=$(LDFLAGS) goreleaser release --snapshot --verbose --clean

# TODO: test upload to dockerhub
release: validate tag-semver ghcr-login ## release to prod
	@echo "Releasing to prod..."
	export GITHUB_TOKEN=$(GITHUB_TOKEN) && \
	export DOCKER_REG=$(DOCKER_REG) && \
	export DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) && \
	export COMPOSE_DOCKER_CLI_BUILD=$(COMPOSE_DOCKER_CLI_BUILD) && \
	LDFLAGS=$(LDFLAGS) goreleaser release --verbose --clean

help: ## show this help
	@echo ''
	@echo 'Usage:'
	@echo '    ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)
