// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISingleSidedVault
/// @notice Interface for the single-sided liquidity vault
interface ISingleSidedVault {
    // ─── Structs ────────────────────────────────────────────────────

    struct Asset {
        uint256 totalDeposits;
        uint256 totalShares;
        uint256 accumulatedYield;
        bool active;
    }

    // ─── Events ─────────────────────────────────────────────────────

    event Deposited(
        address indexed asset,
        address indexed lp,
        uint256 amount,
        uint256 sharesMinted
    );

    event Withdrawn(
        address indexed asset,
        address indexed lp,
        uint256 amount,
        uint256 sharesBurned
    );

    event YieldAccrued(address indexed asset, uint256 amount);

    event PayoutExecuted(
        address indexed asset,
        address indexed to,
        uint256 amount
    );

    event JITRouted(
        address indexed assetIn,
        address indexed assetOut,
        uint256 amount,
        address indexed to
    );

    // ─── Errors ─────────────────────────────────────────────────────

    error ZeroAmount();
    error InsufficientInventory();
    error InsufficientShares();
    error Unauthorized();
    error AssetNotActive();

    // ─── Functions ──────────────────────────────────────────────────

    function deposit(address asset, uint256 amount) external returns (uint256 sharesMinted);

    function withdraw(address asset, uint256 shares) external returns (uint256 amount);

    function payout(address asset, address to, uint256 amount) external;

    function jitSettle(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        address to
    ) external;

    function balanceOf(address asset) external view returns (uint256);

    function sharesOf(address asset, address lp) external view returns (uint256);

    function getAssetInfo(address asset) external view returns (Asset memory);
}
