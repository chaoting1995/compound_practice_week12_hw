// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./helper/MyERC20.sol";
// import "./helper/TestCompoundSetUpTokenA.t.sol";
import "./helper/TestCompoundSetUpTokenB.t.sol";

contract TestCompound is TestCompoundSetUpTokenB {
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2"); // liquidator
    uint256 public initialTokenABalance;
    uint256 public initialTokenBBalance;
    uint256 public borrowTokenABalance;

    function setUp() public override {
        super.setUp(); //init cTokenA, cTokenB

        initialTokenABalance = 100 * 10 ** tokenA.decimals();
        initialTokenBBalance = 1 * 10 ** tokenB.decimals();
        borrowTokenABalance = 50 * 10 ** tokenA.decimals();
        
        vm.startPrank(admin);

        // 給 User1  100 顆（100 * 10^18） TokenA
        tokenA.mint(user1, initialTokenABalance);
        // 給 User1  1 顆（1 * 10^18） TokenB
        tokenB.mint(user1, initialTokenBBalance);

        // 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
        priceOracle.setDirectPrice(address(tokenA), 1 * 1e18);
        priceOracle.setDirectPrice(address(tokenB), 100 * 1e18);

        vm.stopPrank();
    }

    function test_initial_balance() public {
        console.log("initialTokenABalance", initialTokenABalance); // 100_000000000000000000
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
        console.log("cTokenA balance before mint",cTokenA.balanceOf(user1)); // 100_000000000000000000

        // 再用 100 cERC20 token redeem 回 100 顆 ERC20
        cTokenA.redeem(initialTokenABalance);
        console.log("cTokenA balance before redeem",cTokenA.balanceOf(user1)); // 0

        assertEq(tokenA.balanceOf(user1), initialTokenABalance);
        vm.stopPrank();
    }

    // 讓 User1 borrow/repay
    function test_borrow_and_repay() public {
      vm.startPrank(user1);

      // 由 user1 調用 unitroller 的 enterMarkets 方法
      // 因為 mintAllowed 函數會檢查：require(markets[cToken].isListed), 故即使在mint中也需要先調用enterMarkets
      address[] memory cTokenAddresses = new address[](2);
      cTokenAddresses[0] = address(cTokenB);
      cTokenAddresses[1] = address(cTokenA);
      unitrollerProxy.enterMarkets(cTokenAddresses);

      // Token B 的 collateral factor 為 50%, setting within `TestCompoundSetUpTokenB`

      // User1 使用 1 顆 token B 來 mint cToken
      tokenB.approve(address(cTokenB), initialTokenBBalance);
      cTokenB.mint(initialTokenBBalance);

      (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(user1);
      console.log("error",error);
      console.log("liquidity",liquidity);
      console.log("shortfall",shortfall);

      // User1 使用 token B 作為抵押品來借出 50 顆 token A
      cTokenA.borrow(borrowTokenABalance);

      // 檢查 user1 TokenA 的餘額，應為 初始 100A + 借來的 50A，共 150A
      assertEq(tokenA.balanceOf(user1), borrowTokenABalance + initialTokenABalance);

      // 還款
      tokenA.approve(address(cTokenA), borrowTokenABalance);
      cTokenA.repayBorrow(borrowTokenABalance);
      
      // 檢查 user1 TokenA 的餘額，應為 初始 100A 
      assertEq(tokenA.balanceOf(user1), initialTokenABalance);
      
      vm.stopPrank();
    }

    // 延續 (3.) 的借貸場景，調整 token B 的 collateral factor，讓 User1 被 User2 清算
    function test_user2_liquidate_user1_by_modifier_collateral_factor() public {
      vm.startPrank(user1);

      address[] memory cTokenAddress = new address[](2);
      cTokenAddress[0] = address(cTokenB);
      cTokenAddress[1] = address(cTokenA);
      unitrollerProxy.enterMarkets(cTokenAddress);
      
      // ------------------------------------------------------------------------------
      // (3.) 的借貸場景
      // mint 1 顆 tokenA(CTokenA)
      tokenB.approve(address(cTokenB), initialTokenBBalance);
      cTokenB.mint(initialTokenBBalance);

      // User1 使用 token B 作為抵押品來借出 50 顆 token A
      cTokenA.borrow(borrowTokenABalance);
      // ------------------------------------------------------------------------------
      // 借好借滿，此時 user1 的 Account liquidity = 0
      // accountLiquidity = collatarelBalanceOfCTokenB * exchangeRateOfCTokenB * oraclePriceOfCTokenB * collateralFactorOfCTokenB - borrowBalanceOfCTokenA * oraclePriceOfCTokenA
      // = 1B * 1 * 100USD/B * 50% - 50B * 1USD/A = 0

      vm.stopPrank();

      // ------------------------------------------------------------------------------
      vm.startPrank(admin); // admin 才能 -> 調整 tokenB 的 Collateral Factor & mint tokenA
      
      // 調整 tokenB 的 Collateral Factor 50% -> 40%
      // accountLiquidity = 1B * 1 * 100USD/B * 40% - 50B * 1USD/A = -10
      unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 40 / 100 * 1e18);

      // 給 Liquidator User2 50 顆（50 * 10^18） TokenA，使其具備清算能力
      tokenA.mint(user2, borrowTokenABalance);

      vm.stopPrank();
      
      // ------------------------------------------------------------------------------
      vm.startPrank(user2);
      
      // 檢查 user1 可否被清算
      (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(user1);
      
      // shortfall > 0 即 liquidity 實際上 < 0，代表 user1 可被清算
      if (error == 0 && liquidity == 0 && shortfall > 0) {
        
        // user1 的可被清算債務 = 債務 * 清算係數 = 50A * 50% = 25A
        // 該處設定還 10A
        uint repayAmountOfTokenA = 10 * tokenA.decimals();

        CTokenInterface cTokenBCollateral = CTokenInterface(address(cTokenB));

        // user2 發動清算
        tokenA.approve(address(cTokenA), borrowTokenABalance);
        cTokenA.liquidateBorrow(user1, repayAmountOfTokenA, cTokenBCollateral);
        vm.stopPrank();
      }
      
      // 清算成功，獲得抵押品 cTokenB
      console.log("user2", cTokenB.balanceOf(user2));
    }

    // 延續 (3.) 的借貸場景，調整 oracle 中 token B 的價格，讓 User1 被 User2 清算
    function test_user2_liquidate_user1_by_modifier_oracleprice_of_tokenb() public {
      vm.startPrank(user1);

      // setting within `TestCompoundSetUpTokenA` & `TestCompoundSetUpTokenB`
      address[] memory cTokenAddresses = new address[](2);
      cTokenAddresses[0] = address(cTokenB);
      cTokenAddresses[1] = address(cTokenA);
      unitrollerProxy.enterMarkets(cTokenAddresses);
      
      // ------------------------------------------------------------------------------
      // (3.) 的借貸場景
      // mint 1 顆 tokenA(CTokenA)
      tokenB.approve(address(cTokenB), initialTokenBBalance);
      cTokenB.mint(initialTokenBBalance);

      // User1 使用 token B 作為抵押品來借出 50 顆 token A
      cTokenA.borrow(borrowTokenABalance);
      // ------------------------------------------------------------------------------
      // 借好借滿，此時 user1 的 Account liquidity = 0
      // accountLiquidity = collatarelBalanceOfCTokenB * exchangeRateOfCTokenB * oraclePriceOfCTokenB * collateralFactorOfCTokenB - borrowBalanceOfCTokenA * oraclePriceOfCTokenA
      // = 1B * 1 * 100USD/B * 50% - 50B * 1USD/A = 0

      vm.stopPrank();

      // ------------------------------------------------------------------------------
      vm.startPrank(admin); // admin 才能 -> 調整 調整 token B 的 oracle price

      // 調整 tokenB 的 Oracle Price 100USD/B -> 10USD/B
      // accountLiquidity = 1B * 1 * 10USD/B * 50% - 50B * 1USD/A = 5 - 50 = -45
      priceOracle.setDirectPrice(address(tokenB), 1 * 1e18);
      
      // 給 Liquidator User2 50 顆（50 * 10^18） TokenA，使其具備清算能力
      tokenA.mint(user2, borrowTokenABalance);

      vm.stopPrank();

      // ------------------------------------------------------------------------------

      vm.startPrank(user2);

      // 檢查 user1 可否被清算
      (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(user1);
      
      // shortfall > 0 即 liquidity 實際上 < 0，代表 user1 可被清算
      if (error == 0 && liquidity == 0 && shortfall > 0) {
        
        // user1 的可被清算債務 = 債務 * 清算係數 = 50A * 50% = 25A
        // 該處設定還 10A
        uint repayAmountOfTokenA = 10 * 10 ** tokenA.decimals();

        CTokenInterface cTokenBCollateral = CTokenInterface(address(cTokenB));

        // user2 發動清算
        tokenA.approve(address(cTokenA), borrowTokenABalance);
        cTokenA.liquidateBorrow(user1, repayAmountOfTokenA, cTokenBCollateral);
      }

      // 清算成功，獲得抵押品 cTokenB
      console.log("user2", cTokenB.balanceOf(user2));
      
      vm.stopPrank();
    }
}
