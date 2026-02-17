SHELL := bash

.PHONY: help demo-local demo-local-clean keeper-build keeper-demo keeper-self-test

help:
	@echo ""
	@echo "OpenSub developer commands"
	@echo "--------------------------"
	@echo "make demo-local         Run one-command local demo: Anvil -> DemoScenario -> keeper collects once"
	@echo "make keeper-self-test   Run keeper Milestone 5.1 self-test (break allowance -> backoff -> restore -> retry success)"
	@echo "make demo-local-clean   Remove local demo artifacts (./.secrets)"
	@echo "make keeper-build       Build the Rust keeper (release)"
	@echo ""

# One-command local demo (requires: foundry (anvil/forge/cast) + rust/cargo)
demo-local:
	@bash script/demo_local.sh

# Keeper Milestone 5.1 self-test (requires: foundry + rust/cargo)
keeper-self-test:
	@bash script/keeper_self_test.sh

demo-local-clean:
	@rm -rf .secrets

keeper-build:
	@cargo build --release --manifest-path keeper-rs/Cargo.toml

# Alias (historical)
keeper-demo: demo-local
