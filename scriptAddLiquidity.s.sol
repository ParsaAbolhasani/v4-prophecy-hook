// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

/// @title AddLiquidityScript
/// @notice Seeds initial liquidity into the Prophecy pool
contract AddLiquidityScript is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        uint24 fee = uint24(vm.envUint("POOL_FEE"));
        int24 tickSpacing = int24(vm.envInt("TICK_SPACING"));
        int24 tickLower = int24(vm.envInt("TICK_LOWER"));
        int24 tickUpper = int24(vm.envInt("TICK_UPPER"));
        int256 liquidityDelta = int256(vm.envUint("LIQUIDITY_DELTA"));

        vm.startBroadcast(deployerKey);

        // ─── Build PoolKey ──────────────────────────────────────────
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });

        // ─── Modify Liquidity ───────────────────────────────────────
        PoolModifyLiquidityTest modifyLiquidity = PoolModifyLiquidityTest(
            vm.envAddress("MODIFY_LIQUIDITY_TEST")
        );

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            salt: bytes32(0)
        });

        modifyLiquidity.modifyLiquidity(poolKey, params, new bytes(0));

        console.log("Liquidity added to pool:");
        console.log("  PoolId:", vm.toString(PoolId.unwrap(poolKey.toId())));
        console.log("  Liquidity delta:", vm.toString(liquidityDelta));

        vm.stopBroadcast();
    }
}
