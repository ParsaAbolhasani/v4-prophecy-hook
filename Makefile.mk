# Makefile
.PHONY: install build test test-fork coverage clean deploy-local deploy-sepolia fmt snapshot

# ─── Setup ──────────────────────────────────────────────────────────
install:
	forge install foundry-rs/forge-std
	forge install Uniswap/v4-core
	forge install Uniswap/v4-periphery
	forge install OpenZeppelin/openzeppelin-contracts
	forge install transmissions11/solmate
	npm install @pythnetwork/pyth-sdk-solidity

# ─── Build ──────────────────────────────────────────────────────────
build:
	forge build

# ─── Test ───────────────────────────────────────────────────────────
test:
	forge test -vvv

test-fork:
	forge test --fork-url $(MAINNET_RPC_URL) --match-path "test/Fork.t.sol" -vvv

coverage:
	forge coverage --report lcov

snapshot:
	forge snapshot

# ─── Format ─────────────────────────────────────────────────────────
fmt:
	forge fmt

# ─── Deploy ─────────────────────────────────────────────────────────
deploy-local:
	forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

deploy-sepolia:
	forge script script/Deploy.s.sol --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify

# ─── Clean ──────────────────────────────────────────────────────────
clean:
	forge clean
	rm -rf cache out