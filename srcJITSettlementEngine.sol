// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IJITSettlementEngine} from "./interfaces/IJITSettlementEngine.sol";

/// @title JITSettlementEngine
/// @notice Handles just-in-time settlement when vault inventory is short
/// @dev Uses Uniswap v4 flash accounting for atomic conversions
contract JITSettlementEngine is IJITSettlementEngine, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── State ──────────────────────────────────────────────────────

    /// @notice PoolManager reference for flash swaps
    IPoolManager public immutable poolManager;

    /// @notice Vault address authorized to route JIT
    address public immutable vault;

    /// @notice Allowed swap routers
    mapping(address => bool) public allowedRouters;

    // ─── Modifiers ──────────────────────────────────────────────────

    modifier onlyVault() {
        if (msg.sender != vault) revert Unauthorized();
        _;
    }

    modifier onlyAllowedRouter() {
        if (!allowedRouters[msg.sender]) revert Unauthorized();
        _;
    }

    // ─── Constructor ────────────────────────────────────────────────

    constructor(address _poolManager, address _vault) {
        require(_poolManager != address(0), "invalid pool manager");
        require(_vault != address(0), "invalid vault");
        poolManager = IPoolManager(_poolManager);
        vault = _vault;
    }

    // ─── Admin ──────────────────────────────────────────────────────

    function setRouter(address router, bool allowed) external {
        // In production: add access control
        allowedRouters[router] = allowed;
    }

    // ─── External Functions ─────────────────────────────────────────

    /// @inheritdoc IJITSettlementEngine
    function settleJIT(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        address recipient
    ) external override onlyVault nonReentrant returns (uint256 amountIn) {
        // Transfer assetIn from vault
        IERC20(assetIn).safeTransferFrom(vault, address(this), amountOut);

        // In production: execute flash swap via PoolManager
        // For MVP: direct swap via external router
        // amountIn = _executeSwap(assetIn, assetOut, amountOut, recipient);

        // Simplified: assume 1:1 for MVP
        amountIn = amountOut;

        // Transfer assetOut to recipient
        IERC20(assetOut).safeTransfer(recipient, amountOut);

        emit JITSettled(assetIn, assetOut, amountIn, amountOut, recipient);
    }

    /// @inheritdoc IJITSettlementEngine
    function settleFallback(
        address asset,
        uint256 amount,
        address recipient
    ) external override onlyVault nonReentrant {
        // Transfer fallback asset to recipient
        IERC20(asset).safeTransfer(recipient, amount);

        emit FallbackUsed(asset, amount, recipient);
    }

    // ─── Internal Functions ─────────────────────────────────────────

    /// @dev Executes a swap via Uniswap v4 flash accounting
    /// @param assetIn Input asset address
    /// @param assetOut Output asset address
    /// @param amountOut Desired output amount
    /// @param recipient Recipient of output
    /// @return amountIn Actual input consumed
    function _executeSwap(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        address recipient
    ) internal returns (uint256 amountIn) {
        // In production:
        // 1. Unlock PoolManager
        // 2. Execute swap via unlockCallback
        // 3. Settle deltas
        // 4. Return actual input

        // Placeholder for MVP
        return amountOut;
    }
}
