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

import "./MyERC20.sol";

contract TestCompoundSetUpTokenA is Test {
    MyERC20 public tokenA;
    CErc20Delegator public cTokenA;
    CErc20Delegate public cTokenADelegate;
    WhitePaperInterestRateModel	public whitePaperInterestRateModel;
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    SimplePriceOracle public priceOracle;

    address public admin = vm.envAddress("MY_ADDRESS");

    function setUp() public virtual {
      vm.startPrank(admin);

      unitroller = new Unitroller();
      unitrollerProxy = Comptroller(address(unitroller));
      comptroller = new Comptroller();
      priceOracle = new SimplePriceOracle();

      unitroller._setPendingImplementation(address(comptroller));
      comptroller._become(unitroller);

      unitrollerProxy._setCloseFactor(0.5 * 1e18);
      unitrollerProxy._setLiquidationIncentive(1.05 * 1e18);
      unitrollerProxy._setPriceOracle(priceOracle);

      // ------------------------------------------------------------------------------------

      tokenA = new MyERC20("TokenA", "A");

      // 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
      whitePaperInterestRateModel = new WhitePaperInterestRateModel(0,0);
      
      // 部署 CErc20Delegator 的 Implementation 合約 CErc20Delegate
      cTokenADelegate = new CErc20Delegate();

      // ------------------------------------------------------------------------------------
      
      cTokenA = new CErc20Delegator(
          address(tokenA),
          ComptrollerInterface(address(unitroller)),
          InterestRateModel(address(whitePaperInterestRateModel)),
          1e18,
          "cTokenA",
          "cA",
          18,
          payable(admin),
          address(cTokenADelegate),
          new bytes(0x0)
      );

      // ------------------------------------------------------------------------------------
      
      cTokenA._setReserveFactor(0.1 * 1e18);
      unitrollerProxy._supportMarket(CToken(address(cTokenA)));
      unitrollerProxy._setCollateralFactor(CToken(address(cTokenA)), 0.8 * 1e18);
      priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);

      vm.stopPrank();
    }
}