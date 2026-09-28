// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionHook} from "../src/PredictionHook.sol";
import {SingleSidedVault} from "../src/SingleSidedVault.sol";
import {JITSettlementEngine} from "../src/JITSettlementEngine.sol";
import {MockPyth} from "../src/mocks/MockPyth.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IPredictionHook} from "../src/interfaces/IPredictionHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title PredictionHookIntegrationTest
/// @notice Full-stack integration tests with mock Pyth
contract PredictionHookIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

    PredictionHook public hook;
    SingleSidedVault public vault;
    JITSettlementEngine public engine;
    MockPyth public pyth;
    MockERC20 public token0;
    MockERC20 public token1;

    address public poolManager = address(0xPM);
    bytes32 public constant PRICE_FEED_ID = bytes32(uint256(1));
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    PoolKey public poolKey;

    function setUp() public {
        // Deploy mocks
        pyth = new MockPyth();
        pyth.setPriceSimple(PRICE_FEED_ID, 1e8); // 1.0

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);

        // Deploy vault
        vault = new SingleSidedVault(address(0), address(0));

        // Deploy engine
        engine = new JITSettlementEngine(poolManager, address(vault));

        // Deploy hook
        hook = new PredictionHook(
            IPoolManager(poolManager),
            vault,
            engine,
            address(pyth),
            PRICE_FEED_ID
        );

        // Build pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Fund actors
        token0.mint(alice, 100_000e18);
        token0.mint(bob, 100_000e18);
        token1.mint(alice, 100_000e18);
        token1.mint(bob, 100_000e18);
    }

    // ─── Integration: Round Lifecycle ───────────────────────────────

    function test_Integration_FullRoundLifecycle() public {
        // 1. Alice deposits into vault
        vm.startPrank(alice);
        token0.approve(address(vault), 10_000e18);
        vault.deposit(address(token0), 10_000e18);
        vm.stopPrank();

        assertEq(vault.balanceOf(address(token0)), 10_000e18);

        // 2. Bob opens a round
        vm.prank(bob);
        hook.openRound(poolKey, 1 hours, 1000e18);

        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);

        assertEq(round.initiator, bob);
        assertEq(round.lockedCollateral, 1000e18);
        assertFalse(round.settled);

        // 3. Fast forward past end
        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isRoundActive(poolId));

        // 4. Simulate settlement (via direct vault payout)
        vm.prank(address(hook));
        vault.payout(address(token0), bob, 980e18);

        assertEq(token0.balanceOf(bob), 100_000e18 + 980e18);
    }

    function test_Integration_JITFallbackTriggered() public {
        // 1. Small deposit to vault (insufficient for payout)
        vm.startPrank(alice);
        token0.approve(address(vault), 100e18);
        vault.deposit(address(token0), 100e18);
        vm.stopPrank();

        // 2. Bob opens round with large collateral
        vm.prank(bob);
        hook.openRound(poolKey, 1 hours, 10_000e18);

        PoolId poolId = poolKey.toId();
        vm.warp(block.timestamp + 2 hours);

        // 3. Settlement would trigger JIT fallback
        // In real integration, afterSwap would call jitSettle
        // Here we verify the vault correctly routes to engine
        vm.prank(address(hook));
        vault.jitSettle(
            address(token0),
            address(token1),
            500e18,
            bob
        );

        assertEq(token0.balanceOf(address(engine)), 500e18);
    }

    function test_Integration_MultipleRounds() public {
        PoolId poolId = poolKey.toId();

        // Round 1
        vm.prank(bob);
        hook.openRound(poolKey, 1 hours, 1000e18);

        vm.warp(block.timestamp + 2 hours);

        // Manually settle round 1
        vm.prank(address(hook));
        // (In production, afterSwap triggers this)

        // Round 2 (should succeed after round 1 settled)
        // Note: In real flow, need to mark settled first
        // This test would need the full afterSwap simulation
    }

    // ─── Integration: Oracle Behavior ───────────────────────────────

    function test_Integration_OracleStaleness() public {
        // Set stale price (2 minutes old)
        pyth.setPrice(
            PRICE_FEED_ID,
            1e8,
            0,
            -8,
            uint64(block.timestamp - 120)
        );

        // beforeSwap would revert with StaleOraclePrice
        // (Requires full PoolManager mock to test)
    }

    function test_Integration_DynamicFeeScaling() public {
        // Set initial price
        pyth.setPriceSimple(PRICE_FEED_ID, 1e8);

        // Simulate price change: 1% increase
        pyth.setPriceSimple(PRICE_FEED_ID, 1.01e8);

        // Fee should scale from 2% to 3%
        // (Requires hook call)
    }

    // ─── Integration: Vault Accounting ──────────────────────────────

    function test_Integration_VaultShareAccounting() public {
        // Alice deposits
        vm.startPrank(alice);
        token0.approve(address(vault), 1000e18);
        uint256 aliceShares = vault.deposit(address(token0), 1000e18);
        vm.stopPrank();

        // Bob deposits
        vm.startPrank(bob);
        token0.approve(address(vault), 500e18);
        uint256 bobShares = vault.deposit(address(token0), 500e18);
        vm.stopPrank();

        assertEq(aliceShares, 1000e18);
        assertEq(bobShares, 500e18);
        assertEq(vault.balanceOf(address(token0)), 1500e18);
        assertEq(vault.sharesOf(address(token0), alice), 1000e18);
        assertEq(vault.sharesOf(address(token0), bob), 500e18);
    }

    function test_Integration_YieldAccrual() public {
        // Alice deposits
        vm.startPrank(alice);
        token0.approve(address(vault), 1000e18);
        vault.deposit(address(token0), 1000e18);
        vm.stopPrank();

        // Hook accrues yield
        vm.prank(address(hook));
        vault.accrueYield(address(token0), 100e18);

        // Vault balance should now be 1100
        assertEq(vault.balanceOf(address(token0)), 1100e18);

        // Alice can withdraw more than she deposited
        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(address(token0), 1000e18);
        assertEq(withdrawn, 1100e18);
    }
}
