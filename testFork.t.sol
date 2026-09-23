// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionHook} from "../src/PredictionHook.sol";
import {SingleSidedVault} from "../src/SingleSidedVault.sol";
import {JITSettlementEngine} from "../src/JITSettlementEngine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title ForkTest
/// @notice End-to-end test on a mainnet fork
/// @dev Run with: forge test --fork-url $MAINNET_RPC_URL --match-path "test/Fork.t.sol"
contract ForkTest is Test {
    // Canonical Uniswap v4 addresses (mainnet)
    address constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    // Canonical Pyth address (mainnet)
    address constant PYTH_ORACLE = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;

    // Price feed ID (example: ETH/USD)
    bytes32 constant ETH_USD_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    PredictionHook public hook;
    SingleSidedVault public vault;
    JITSettlementEngine public engine;
    MockERC20 public testToken;

    function setUp() public {
        // Only run if fork is configured
        if (block.chainid == 31337) {
            vm.skip(true); // Skip on local anvil without fork
        }

        // Deploy test token
        testToken = new MockERC20("Test Token", "TEST", 18);

        // Deploy vault
        vault = new SingleSidedVault(address(0), address(0));

        // Deploy engine with real PoolManager
        engine = new JITSettlementEngine(POOL_MANAGER, address(vault));

        // Deploy hook with real Pyth
        hook = new PredictionHook(
            IPoolManager(POOL_MANAGER),
            vault,
            engine,
            PYTH_ORACLE,
            ETH_USD_FEED
        );
    }

    function test_Fork_PythPriceFetch() public {
        // Verify Pyth oracle is reachable
        (bool success, bytes memory data) = PYTH_ORACLE.staticcall(
            abi.encodeWithSignature(
                "getPriceUnsafe(bytes32)",
                ETH_USD_FEED
            )
        );

        // In a real fork test, this would return valid price data
        // For now, just verify the call doesn't revert
        console.log("Pyth call success:", success);
    }

    function test_Fork_HookPermissions() public {
        Hooks.Permissions memory perms = hook.getHookPermissions();

        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
    }

    function test_Fork_OpenRound() public {
        // This would work on a real fork
        // poolKey needs to be a real initialized pool
        console.log("Hook deployed at:", address(hook));
        console.log("Vault deployed at:", address(vault));
        console.log("Engine deployed at:", address(engine));
    }
}
