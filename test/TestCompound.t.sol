// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./helper/TestCompoundSetup.t.sol";

contract TestCompound is TestCompoundSetUpTokenB {
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2"); // liquidator

    function setUp() public override {
        super.setUp();
 
        vm.stopPrank();
    }
}
