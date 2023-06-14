// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/ComptrollerInterface.sol";

import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";

import "compound-protocol/contracts/InterestRateModel.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";

import "./TestCompoundSetUpTokenA.t.sol";
import "./MyERC20.sol";

contract TestCompoundSetUpTokenB is TestCompoundSetUpTokenA {
    MyERC20 public tokenB;
    CErc20Delegator public cTokenB;
    CErc20Delegate public cTokenBDelegate;
    WhitePaperInterestRateModel	public whitePaperInterestRateModelB;
    // Unitroller public unitroller;
    // Comptroller public comptroller;
    // Comptroller public unitrollerProxy;
    // SimplePriceOracle public priceOracle;

    // address public admin = vm.envAddress("MY_ADDRESS");

    function setUp() public virtual override {
      super.setUp(); //init cTokenA

      vm.startPrank(admin);

      // unitroller = new Unitroller();
      // unitrollerProxy = Comptroller(address(unitroller));
      // comptroller = new Comptroller();
      // priceOracle = new SimplePriceOracle();

      // unitroller._setPendingImplementation(address(comptroller));
      // comptroller._become(unitroller);

      unitrollerProxy._setCloseFactor(0.5 * 1e18);
      unitrollerProxy._setLiquidationIncentive(1.05 * 1e18);
      unitrollerProxy._setPriceOracle(priceOracle);

      // ------------------------------------------------------------------------------------

      tokenB = new MyERC20("TokenB", "B");

      // 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
      whitePaperInterestRateModelB = new WhitePaperInterestRateModel(0,0);
      
      // 部署 CErc20Delegator 的 Implementation 合約 CErc20Delegate
      cTokenBDelegate = new CErc20Delegate();

      // ------------------------------------------------------------------------------------
      
      cTokenB = new CErc20Delegator(
          address(tokenB),
          ComptrollerInterface(address(unitroller)),
          InterestRateModel(address(whitePaperInterestRateModelB)),
          1e18,
          "cTokenB",
          "cB",
          18,
          payable(admin),
          address(cTokenBDelegate),
          new bytes(0x00)
      );

      // ------------------------------------------------------------------------------------
      
      cTokenB._setReserveFactor(0.25 * 1e18);
      cTokenB._setImplementation(address(cTokenBDelegate), false, new bytes(0x00));

      unitrollerProxy._supportMarket(CToken(address(cTokenB)));

      // 注意：先設定 OraclePrice 再設定 CollateralFactor
      priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 1e18);
      // Token B 的 collateral factor 為 50%
      unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 0.5 * 1e18);
      
      vm.stopPrank();
    }
}