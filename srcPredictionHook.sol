// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {IPredictionHook} from "./interfaces/IPredictionHook.sol";
import {ISingleSidedVault} from "./interfaces/ISingleSidedVault.sol";
import {IJITSettlementEngine} from "./interfaces/IJITSettlementEngine.sol";
import {SettlementMath} from "./libraries/SettlementMath.sol";
import {HookPermissions} from "./libraries/HookPermissions.sol";

/// @title PredictionHook
/// @notice Uniswap v4 hook powering asset-backed prediction markets
/// @dev Implements beforeSwap (dynamic fee + oracle) and afterSwap (settlement)
contract PredictionHook is BaseHook, IPredictionHook {
    using PoolIdLibrary for PoolKey;

    // ─── Constants ──────────────────────────────────────────────────

    uint256 public constant BASE_HOUSE_EDGE_BPS = 200; // 2%
    uint256 public constant MAX_HOUSE_EDGE_BPS = 500;  // 5%
    uint256 public constant CONFIDENCE_THRESHOLD_BPS = 100; // 1%
    uint256 public constant MAX_ORACLE_AGE = 60; // 60 seconds

    // ─── State ──────────────────────────────────────────────────────

    /// @notice House vault for LP deposits and payouts
    ISingleSidedVault public immutable houseVault;

    /// @notice JIT settlement engine
    IJITSettlementEngine public immutable settlementEngine;

    /// @notice Pyth oracle address
    address public immutable pythOracle;

    /// @notice Pyth price feed ID for volatile asset
    bytes32 public immutable priceFeedId;

    /// @notice Active rounds per pool
    mapping(PoolId => Round) private _rounds;

    /// @notice Last known price per pool (for volatility calc)
    mapping(PoolId => int64) private _lastPrices;

    // ─── Constructor ────────────────────────────────────────────────

    constructor(
        IPoolManager _poolManager,
        ISingleSidedVault _houseVault,
        IJITSettlementEngine _settlementEngine,
        address _pythOracle,
        bytes32 _priceFeedId
    ) BaseHook(_poolManager) {
        require(address(_houseVault) != address(0), "invalid vault");
        require(address(_settlementEngine) != address(0), "invalid engine");
        require(_pythOracle != address(0), "invalid oracle");

        houseVault = _houseVault;
        settlementEngine = _settlementEngine;
        pythOracle = _pythOracle;
        priceFeedId = _priceFeedId;
    }

    // ─── Hook Permissions ───────────────────────────────────────────

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return HookPermissions.getProphecyPermissions();
    }

    // ─── beforeSwap ─────────────────────────────────────────────────

    /// @notice Checks Pyth oracle, computes dynamic fee
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();

        // 1. Fetch oracle price
        (int64 price, uint64 publishTime, uint64 conf) = _getPythPrice();

        // 2. Validate freshness
        if (block.timestamp - publishTime > MAX_ORACLE_AGE) {
            revert StaleOraclePrice();
        }

        // 3. Validate confidence interval
        uint256 confidenceBps = (uint256(conf) * 10_000) /
            uint256(uint64(price));
        if (confidenceBps > CONFIDENCE_THRESHOLD_BPS) {
            revert LowConfidenceOracle();
        }

        // 4. Compute volatility from last price
        int64 lastPrice = _lastPrices[poolId];
        uint256 volatilityBps = SettlementMath.computeVolatilityBps(
            price,
            lastPrice
        );

        // 5. Compute dynamic fee
        uint256 dynamicFeeBps = SettlementMath.computeDynamicFee(
            BASE_HOUSE_EDGE_BPS,
            volatilityBps
        );

        // 6. Store state
        _lastPrices[poolId] = price;
        _rounds[poolId].dynamicFeeBps = dynamicFeeBps;

        emit DynamicFeeAdjusted(poolId, dynamicFeeBps, price);

        // 7. Return fee override (converted to pips: 1 bps = 100 pips)
        uint24 feePips = uint24(dynamicFeeBps * 100);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feePips
        );
    }

    // ─── afterSwap ──────────────────────────────────────────────────

    /// @notice Handles settlement and transient liquidity accrual
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        Round storage round = _rounds[poolId];

        // If no active round, nothing to do
        if (round.startTime == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // If round already settled, skip
        if (round.settled) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Check if round expired
        if (block.timestamp >= round.endTime) {
            _settleRound(poolId, key);
        } else {
            // Round active: accrue transient liquidity
            uint256 swapAmount = _absDelta(delta);
            round.lockedCollateral += swapAmount;
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // ─── Settlement ─────────────────────────────────────────────────

    function _settleRound(PoolId poolId, PoolKey calldata key) internal {
        Round storage round = _rounds[poolId];

        uint256 payout = SettlementMath.computePayout(
            round.lockedCollateral,
            round.dynamicFeeBps
        );

        address asset = Currency.unwrap(key.currency0);
        address winner = round.initiator;

        // Try direct payout
        uint256 vaultBalance = houseVault.balanceOf(asset);

        bool usedJIT = false;

        if (vaultBalance >= payout) {
            // Direct payout from vault
            houseVault.payout(asset, winner, payout);
        } else {
            // JIT fallback
            usedJIT = true;
            address assetOut = Currency.unwrap(key.currency1);
            houseVault.jitSettle(asset, assetOut, payout, winner);
        }

        round.settled = true;

        emit RoundSettled(poolId, winner, payout, usedJIT);
    }

    // ─── Round Lifecycle ────────────────────────────────────────────

    /// @inheritdoc IPredictionHook
    function openRound(
        PoolKey calldata key,
        uint64 duration,
        uint256 collateral
    ) external override {
        if (duration == 0 || duration > 7 days) revert InvalidDuration();
        if (collateral == 0) revert InvalidCollateral();

        PoolId poolId = key.toId();
        Round storage round = _rounds[poolId];

        // Check no active round
        if (round.startTime != 0 && !round.settled) {
            revert RoundAlreadyActive();
        }

        _rounds[poolId] = Round({
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + duration),
            lockedCollateral: collateral,
            dynamicFeeBps: BASE_HOUSE_EDGE_BPS,
            initiator: msg.sender,
            settled: false
        });

        emit RoundOpened(poolId, msg.sender, collateral, BASE_HOUSE_EDGE_BPS);
    }

    // ─── View Functions ─────────────────────────────────────────────

    /// @inheritdoc IPredictionHook
    function getRound(
        PoolId poolId
    ) external view override returns (Round memory) {
        return _rounds[poolId];
    }

    /// @inheritdoc IPredictionHook
    function isRoundActive(
        PoolId poolId
    ) external view override returns (bool) {
        Round storage round = _rounds[poolId];
        return round.startTime != 0 &&
            !round.settled &&
            block.timestamp < round.endTime;
    }

    // ─── Internal Helpers ───────────────────────────────────────────

    function _getPythPrice()
        internal
        view
        returns (int64 price, uint64 publishTime, uint64 conf)
    {
        // Interface: IPyth(pythOracle).getPriceNoOlderThan(priceFeedId, age)
        // For MVP, return mock values
        // In production: call actual Pyth oracle

        // Placeholder implementation
        return (1e8, uint64(block.timestamp), 0); // 1.0 price, no confidence
    }

    function _absDelta(BalanceDelta delta) internal pure returns (uint256) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        uint256 abs0 = SettlementMath.absInt128(amount0);
        uint256 abs1 = SettlementMath.absInt128(amount1);

        return abs0 > abs1 ? abs0 : abs1;
    }
}
