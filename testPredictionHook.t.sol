// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PredictionHook} from "../src/PredictionHook.sol";
import {SingleSidedVault} from "../src/SingleSidedVault.sol";
import {JITSettlementEngine} from "../src/JITSettlementEngine.sol";
import {IPredictionHook} from "../src/interfaces/IPredictionHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract PredictionHookTest is Test {
    using PoolIdLibrary for PoolKey;

    PredictionHook public hook;
    SingleSidedVault public vault;
    JITSettlementEngine public engine;

    address public poolManager = address(0xPM);
    address public pythOracle = address(0xPYTH);
    bytes32 public priceFeedId = bytes32(uint256(1));

    PoolKey public poolKey;

    function setUp() public {
        // Deploy contracts
        vault = new SingleSidedVault(address(0), address(0)); // Temp
        engine = new JITSettlementEngine(poolManager, address(vault));

        hook = new PredictionHook(
            IPoolManager(poolManager),
            vault,
            engine,
            pythOracle,
            priceFeedId
        );

        // Configure pool
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    // ─── Permission Tests ───────────────────────────────────────────

    function test_GetHookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();

        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertTrue(perms.afterSwapReturnDelta);
        assertFalse(perms.beforeInitialize);
        assertFalse(perms.afterInitialize);
    }

    // ─── Round Lifecycle Tests ──────────────────────────────────────

    function test_OpenRound_Success() public {
        uint64 duration = 1 hours;
        uint256 collateral = 1000e18;

        hook.openRound(poolKey, duration, collateral);

        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);

        assertEq(round.startTime, block.timestamp);
        assertEq(round.endTime, block.timestamp + duration);
        assertEq(round.lockedCollateral, collateral);
        assertEq(round.initiator, address(this));
        assertFalse(round.settled);
    }

    function test_OpenRound_RevertsOnZeroDuration() public {
        vm.expectRevert(IPredictionHook.InvalidDuration.selector);
        hook.openRound(poolKey, 0, 1000e18);
    }

    function test_OpenRound_RevertsOnZeroCollateral() public {
        vm.expectRevert(IPredictionHook.InvalidCollateral.selector);
        hook.openRound(poolKey, 1 hours, 0);
    }

    function test_OpenRound_RevertsIfActive() public {
        hook.openRound(poolKey, 1 hours, 1000e18);

        vm.expectRevert(IPredictionHook.RoundAlreadyActive.selector);
        hook.openRound(poolKey, 1 hours, 1000e18);
    }

    function test_IsRoundActive() public {
        PoolId poolId = poolKey.toId();

        // No round yet
        assertFalse(hook.isRoundActive(poolId));

        // Open round
        hook.openRound(poolKey, 1 hours, 1000e18);
        assertTrue(hook.isRoundActive(poolId));

        // Fast forward past end
        vm.warp(block.timestamp + 2 hours);
        assertFalse(hook.isRoundActive(poolId));
    }

    // ─── View Tests ─────────────────────────────────────────────────

    function test_GetRound() public {
        hook.openRound(poolKey, 1 hours, 1000e18);

        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);

        assertEq(round.lockedCollateral, 1000e18);
    }

    function test_GetRound_ReturnsEmptyForNonExistent() public {
        PoolId poolId = poolKey.toId();
        IPredictionHook.Round memory round = hook.getRound(poolId);

        assertEq(round.startTime, 0);
        assertEq(round.lockedCollateral, 0);
    }

    // ─── Constants Tests ────────────────────────────────────────────

    function test_Constants() public view {
        assertEq(hook.BASE_HOUSE_EDGE_BPS(), 200);
        assertEq(hook.MAX_HOUSE_EDGE_BPS(), 500);
        assertEq(hook.CONFIDENCE_THRESHOLD_BPS(), 100);
        assertEq(hook.MAX_ORACLE_AGE(), 60);
    }
}
