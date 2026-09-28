// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SingleSidedVault} from "../src/SingleSidedVault.sol";
import {SettlementMath} from "../src/libraries/SettlementMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title GasTest
/// @notice Measures gas consumption of critical operations
contract GasTest is Test {
    SingleSidedVault public vault;
    MockERC20 public token;

    address public hook = address(0x1);
    address public engine = address(0x2);
    address public alice = address(0xA11CE);

    function setUp() public {
        vault = new SingleSidedVault(hook, engine);
        token = new MockERC20("Test", "TEST", 18);
        token.mint(alice, 1_000_000e18);
    }

    function test_Gas_Deposit() public {
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);

        uint256 gasBefore = gasleft();
        vault.deposit(address(token), 1000e18);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Deposit gas:", gasUsed);
        assertLt(gasUsed, 150_000, "Deposit too expensive");
    }

    function test_Gas_Withdraw() public {
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(address(token), 1000e18);

        uint256 gasBefore = gasleft();
        vault.withdraw(address(token), 1000e18);
        uint256 gasUsed = gasBefore - gasleft();

        vm.stopPrank();

        console.log("Withdraw gas:", gasUsed);
        assertLt(gasUsed, 100_000, "Withdraw too expensive");
    }

    function test_Gas_Payout() public {
        vm.startPrank(alice);
        token.approve(address(vault), 1000e18);
        vault.deposit(address(token), 1000e18);
        vm.stopPrank();

        vm.prank(hook);
        uint256 gasBefore = gasleft();
        vault.payout(address(token), alice, 500e18);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Payout gas:", gasUsed);
        assertLt(gasUsed, 80_000, "Payout too expensive");
    }

    function test_Gas_ComputePayout() public view {
        uint256 gasBefore = gasleft();
        SettlementMath.computePayout(1000e18, 200);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("computePayout gas:", gasUsed);
        assertLt(gasUsed, 2_000, "Math too expensive");
    }

    function test_Gas_ComputeShares() public view {
        uint256 gasBefore = gasleft();
        SettlementMath.computeShares(1000e18, 5000e18, 5000e18);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("computeShares gas:", gasUsed);
        assertLt(gasUsed, 2_000, "Math too expensive");
    }
}
