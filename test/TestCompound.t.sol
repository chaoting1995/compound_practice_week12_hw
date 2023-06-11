// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./helper/MyERC20.sol";
// import "./helper/TestCompoundSetUpTokenA.t.sol";
import "./helper/TestCompoundSetUpTokenB.t.sol";

contract TestCompound is TestCompoundSetUpTokenB {
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2"); // liquidator
    uint256 public initialTokenABalance = 100 * tokenA.decimals();
    uint256 public initialTokenBBalance = 1 * tokenB.decimals();

    function setUp() public override {
      super.setUp(); //init cTokenA, cTokenB

      vm.startPrank(admin);
      
      // 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
      priceOracle.setDirectPrice(address(tokenA), 1 * 1e18);
      priceOracle.setDirectPrice(address(tokenB), 10 * 1e18);

      // 給 User1  100 顆（100 * 10^18） TokenA
      tokenA.mint(user1, initialTokenABalance);
      // 給 User1  1 顆（1 * 10^18） TokenB
      tokenB.mint(user1, initialTokenBBalance);
    }

    function test_initial_balance() public {
      console.log("initialTokenABalance", initialTokenABalance);
      assertEq(tokenA.balanceOf(user1),initialTokenABalance);
    }

    // 讓 User1 mint/redeem cERC20
    function test_mint_and_redeem() public {

        vm.startPrank(user1);
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cTokenA);
        unitrollerProxy.enterMarkets(cTokenAddr);

        tokenA.approve(address(cTokenA), 1e18);

        cTokenA.mint(1e18);
        cTokenA.redeem(1e18);

        assertEq(tokenA.balanceOf(user1), 1e18);
    }

    // 讓 User1 borrow/repay
}