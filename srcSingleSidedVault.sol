// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISingleSidedVault} from "./interfaces/ISingleSidedVault.sol";
import {SettlementMath} from "./libraries/SettlementMath.sol";

/// @title SingleSidedVault
/// @notice Passive LPs deposit a single asset and earn yield from the
///         prediction house edge. Acts as automated counterparty.
/// @dev Implements share accounting, yield distribution, and JIT fallback.
contract SingleSidedVault is ISingleSidedVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── State ──────────────────────────────────────────────────────

    /// @notice Hook address authorized to call payout/jitSettle
    address public immutable hook;

    /// @notice JIT settlement engine address
    address public immutable settlementEngine;

    /// @notice Asset info per token address
    mapping(address => Asset) private _assets;

    /// @notice LP shares per asset
    mapping(address => mapping(address => uint256)) private _shares;

    // ─── Modifiers ──────────────────────────────────────────────────

    modifier onlyHook() {
        if (msg.sender != hook) revert Unauthorized();
        _;
    }

    modifier onlyHookOrEngine() {
        if (msg.sender != hook && msg.sender != settlementEngine) {
            revert Unauthorized();
        }
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────

    constructor(address _hook, address _settlementEngine) {
        require(_hook != address(0), "invalid hook");
        require(_settlementEngine != address(0), "invalid engine");
        hook = _hook;
        settlementEngine = _settlementEngine;
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @inheritdoc ISingleSidedVault
    function deposit(
        address asset,
        uint256 amount
    ) external override nonReentrant returns (uint256 sharesMinted) {
        if (amount == 0) revert ZeroAmount();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        Asset storage a = _assets[asset];
        if (!a.active) {
            a.active = true;
        }

        sharesMinted = SettlementMath.computeShares(
            amount,
            a.totalDeposits,
            a.totalShares
        );

        a.totalDeposits += amount;
        a.totalShares += sharesMinted;
        _shares[asset][msg.sender] += sharesMinted;

        emit Deposited(asset, msg.sender, amount, sharesMinted);
    }

    /// @inheritdoc ISingleSidedVault
    function withdraw(
        address asset,
        uint256 shares
    ) external override nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();

        Asset storage a = _assets[asset];
        if (!a.active) revert AssetNotActive();
        if (_shares[asset][msg.sender] < shares) revert InsufficientShares();

        amount = SettlementMath.computeWithdrawAmount(
            shares,
            a.totalDeposits,
            a.totalShares
        );

        _shares[asset][msg.sender] -= shares;
        a.totalShares -= shares;
        a.totalDeposits -= amount;

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdrawn(asset, msg.sender, amount, shares);
    }

    /// @inheritdoc ISingleSidedVault
    function payout(
        address asset,
        address to,
        uint256 amount
    ) external override onlyHook {
        Asset storage a = _assets[asset];
        if (a.totalDeposits < amount) revert InsufficientInventory();

        a.totalDeposits -= amount;
        IERC20(asset).safeTransfer(to, amount);

        emit PayoutExecuted(asset, to, amount);
    }

    /// @inheritdoc ISingleSidedVault
    function jitSettle(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        address to
    ) external override onlyHook {
        // Transfer assetIn to settlement engine for flash swap
        IERC20(assetIn).safeTransfer(settlementEngine, amountOut);

        emit JITRouted(assetIn, assetOut, amountOut, to);
    }

    /// @notice Accrues yield to an asset (called by hook after swap)
    function accrueYield(address asset, uint256 amount) external onlyHookOrEngine {
        Asset storage a = _assets[asset];
        a.accumulatedYield += amount;
        a.totalDeposits += amount;

        emit YieldAccrued(asset, amount);
    }

    // ─── View Functions ─────────────────────────────────────────────

    /// @inheritdoc ISingleSidedVault
    function balanceOf(address asset) external view override returns (uint256) {
        return _assets[asset].totalDeposits;
    }

    /// @inheritdoc ISingleSidedVault
    function sharesOf(
        address asset,
        address lp
    ) external view override returns (uint256) {
        return _shares[asset][lp];
    }

    /// @inheritdoc ISingleSidedVault
    function getAssetInfo(
        address asset
    ) external view override returns (Asset memory) {
        return _assets[asset];
    }
}
