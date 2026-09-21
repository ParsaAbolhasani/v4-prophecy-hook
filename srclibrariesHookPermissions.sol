// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @title HookPermissions
/// @notice Library for hook permission configuration
library HookPermissions {
    /// @notice Returns permissions for the Prophecy hook
    /// @dev Enables beforeSwap and afterSwap with delta return
    function getProphecyPermissions()
        internal
        pure
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,             // Dynamic fee + oracle check
            afterSwap: true,              // Settlement + JIT routing
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false, // We don't override swap delta
            afterSwapReturnDelta: true,   // We return hook delta for fees
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
