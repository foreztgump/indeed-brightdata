.PHONY: install test package clean help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install skill for your AI agent platform
	./install.sh

test: ## Run all bats tests
	bats tests/

package: ## Build ZIP for Claude Desktop upload
	./scripts/package.sh

clean: ## Remove build artifacts
	rm -f indeed-brightdata.zip
