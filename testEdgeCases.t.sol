// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionHook} from "../src/PredictionHook.sol";
import {SingleSidedVault} from "../src/SingleSidedVault.sol";
import {JITSettlementEngine} from "../src/JITSettlementEngine.sol";
import {MockPyth} from "../src/mocks/MockPyth.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IPredictionHook} from "../src/interfaces/IPredictionHook.sol";
import {ISingleSidedVault} from "../src/interfaces/ISingleSidedVault.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title EdgeCasesTest
/// @notice Tests for boundary conditions and attack vectors
contract EdgeCasesTest is Test {
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
    address public attacker = address(0xBAD);

    PoolKey public poolKey;

    function setUp() public {
        pyth = new MockPyth();
        pyth.setPriceSimple(PRICE_FEED_ID, 1e8);

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);

        vault = new SingleSidedVault(address(0), address(0));
        engine = new JITSettlementEngine(poolManager, address(vault));
        hook = new PredictionHook(
            IPoolManager(poolManager),
            vault,
            engine,
            address(pyth),
            PRICE_FEED_ID
        );

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        token0.mint(alice, 1_000_000e18);
        token0.mint(bob, 1_000_000e18);
        token0.mint(attacker, 1_000_000e18);
    }

    // ─── Boundary: Duration ─────────────────────────────────────────

    function test_Edge_MaxDuration() public {
        // 7 days is the max allowed
        hook.openRound(poolKey, 7 days, 1000e18);
        PoolId poolId = poolKey.toId();
        assertTrue(hook.isRoundActive(poolId));
    }

    function test_Edge_JustOverMaxDuration() public {
        vm.expectRevert(IPredictionHook.InvalidDuration.selector);
        hook.openRound(poolKey, 7 days + 1, 1000e18);
    }

    function test_Edge_MinDuration() public {
        hook.openRound(poolKey, 1, 1000e18); // 1 second
        PoolId poolId = poolKey.toId();
        assertTrue(hook.isRoundActive(poolId));
    }

    // ─── Boundary: Collateral ───────────────────────────────────────

    function test_Edge_MinCollateral() public {
        hook.openRound(poolKey, 1 hours, 1); // 1 wei
        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);
        assertEq(round.lockedCollateral, 1);
    }

    function test_Edge_MaxCollateral() public {
        uint256 maxCollateral = type(uint128).max;
        hook.openRound(poolKey, 1 hours, maxCollateral);
        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);
        assertEq(round.lockedCollateral, maxCollateral);
    }

    // ─── Attack: Unauthorized Access ────────────────────────────────

    function test_Attack_UnauthorizedPayout() public {
        vm.startPrank(alice);
        token0.approve(address(vault), 1000e18);
        vault.deposit(address(token0), 1000e18);
        vm.stopPrank();

        // Attacker tries to call payout
        vm.prank(attacker);
        vm.expectRevert(ISingleSidedVault.Unauthorized.selector);
        vault.payout(address(token0), attacker, 1000e18);
    }

    function test_Attack_UnauthorizedJITSettle() public {
        vm.prank(attacker);
        vm.expectRevert(ISingleSidedVault.Unauthorized.selector);
        vault.jitSettle(address(token0), address(token1), 1000e18, attacker);
    }

    function test_Attack_UnauthorizedYieldAccrual() public {
        vm.prank(attacker);
        vm.expectRevert(ISingleSidedVault.Unauthorized.selector);
        vault.accrueYield(address(token0), 1000e18);
    }

    // ─── Attack: Reentrancy ─────────────────────────────────────────

    function test_Attack_ReentrancyOnWithdraw() public {
        // ReentrancyGuard should prevent this
        // Full test requires malicious token implementation
        // Placeholder for security audit
    }

    // ─── Edge: Zero Address Checks ──────────────────────────────────

    function test_Edge_ZeroAddressVault() public {
        vm.expectRevert();
        new PredictionHook(
            IPoolManager(poolManager),
            ISingleSidedVault(address(0)),
            engine,
            address(pyth),
            PRICE_FEED_ID
        );
    }

    function test_Edge_ZeroAddressEngine() public {
        vm.expectRevert();
        new PredictionHook(
            IPoolManager(poolManager),
            vault,
            JITSettlementEngine(address(0)),
            address(pyth),
            PRICE_FEED_ID
        );
    }

    // ─── Edge: Round State Transitions ──────────────────────────────

    function test_Edge_OpenRoundAfterSettle() public {
        PoolId poolId = poolKey.toId();

        // Open round 1
        hook.openRound(poolKey, 1 hours, 1000e18);

        // Cannot open another while active
        vm.expectRevert(IPredictionHook.RoundAlreadyActive.selector);
        hook.openRound(poolKey, 1 hours, 1000e18);

        // Warp past end
        vm.warp(block.timestamp + 2 hours);

        // Round should be inactive
        assertFalse(hook.isRoundActive(poolId));

        // Note: In production, afterSwap would mark settled
        // Then openRound would work again
    }

    // ─── Edge: Multiple Pools ───────────────────────────────────────

    function test_Edge_MultiplePoolsIndependent() public {
        // Create second pool
        PoolKey memory poolKey2 = PoolKey({
            currency0: Currency.wrap(address(token1)),
            currency1: Currency.wrap(address(token0)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Open rounds on both
        hook.openRound(poolKey, 1 hours, 1000e18);
        hook.openRound(poolKey2, 2 hours, 2000e18);

        PoolId poolId1 = poolKey.toId();
        PoolId poolId2 = poolKey2.toId();

        IPredictionHook.Round memory round1 = hook.getRound(poolId1);
        IPredictionHook.Round memory round2 = hook.getRound(poolId2);

        assertEq(round1.lockedCollateral, 1000e18);
        assertEq(round2.lockedCollateral, 2000e18);
    }

    // ─── Edge: Vault with Multiple Assets ───────────────────────────

    function test_Edge_VaultMultipleAssets() public {
        vm.startPrank(alice);
        token0.approve(address(vault), 1000e18);
        token1.approve(address(vault), 2000e18);

        vault.deposit(address(token0), 1000e18);
        vault.deposit(address(token1), 2000e18);
        vm.stopPrank();

        assertEq(vault.balanceOf(address(token0)), 1000e18);
        assertEq(vault.balanceOf(address(token1)), 2000e18);

        // Withdraw from one asset shouldn't affect the other
        vm.prank(alice);
        vault.withdraw(address(token0), 500e18);

        assertEq(vault.balanceOf(address(token0)), 500e18);
        assertEq(vault.balanceOf(address(token1)), 2000e18);
    }
}
