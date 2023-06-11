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

        // 給 User1  100 顆（100 * 10^18） TokenA
        tokenA.mint(user1, initialTokenABalance);
        // 給 User1  1 顆（1 * 10^18） TokenB
        tokenB.mint(user1, initialTokenBBalance);

        // 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
        priceOracle.setDirectPrice(address(tokenA), 1 * 1e18);
        priceOracle.setDirectPrice(address(tokenB), 10 * 1e18);
    }

    function test_initial_balance() public {
        console.log("initialTokenABalance", initialTokenABalance);
        assertEq(tokenA.balanceOf(user1), initialTokenABalance);
    }

    // 讓 User1 mint/redeem cERC20
    function test_mint_and_redeem() public {
        vm.startPrank(user1);

        // setting within `TestCompoundSetUpTokenA`
        // address[] memory cTokenAddresses = new address[](1);
        // cTokenAddresses[0] = address(cTokenA);
        // unitrollerProxy.enterMarkets(cTokenAddresses);

        tokenA.approve(address(cTokenA), initialTokenABalance);

        // User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token
        cTokenA.mint(initialTokenABalance);
        console.log("cTokenA balance",cTokenA.balanceOf(user1));

        // 再用 100 cERC20 token redeem 回 100 顆 ERC20
        cTokenA.redeem(initialTokenABalance);

        assertEq(tokenA.balanceOf(user1), initialTokenABalance);
    }

    // 讓 User1 borrow/repay
    function test_borrow_and_repay() public {
        vm.startPrank(user1);

        // setting within `TestCompoundSetUpTokenA` & `TestCompoundSetUpTokenB`
        // address[] memory cTokenAddresses = new address[](2);
        // cTokenAddresses[0] = address(cTokenB);
        // cTokenAddresses[1] = address(cTokenA);
        // unitrollerProxy.enterMarkets(cTokenAddresses);
        tokenB.approve(address(cTokenB), 1e18);

        // Token B 的 collateral factor 為 50%, setting within `TestCompoundSetUpTokenB`
        // User1 使用 1 顆 token B 來 mint cToken
        // mint 1 顆 tokenA(cTokenA)
        cTokenB.mint(1e18);
        cTokenA.borrow(50e18);
        // 確認原始的 1顆 tokenA (underLyingToken) + 借來的 50顆，共51顆是否正確
        assertEq(tokenA.balanceOf(user1), 50e18 + 1e18);

        // 還錢之前要先 approve
        tokenA.approve(address(cTokenA), 50e18);
        cTokenA.repayBorrow(50e18);
        // 確認是否只剩下原先的 1顆
        assertEq(tokenA.balanceOf(user1), 1e18);
        vm.stopPrank();
    }
}
