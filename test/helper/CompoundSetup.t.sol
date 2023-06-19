// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";

import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";

import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";

import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";

contract CompoundSetup is Test {
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    
    SimplePriceOracle public priceOracle;
    WhitePaperInterestRateModel	public whitePaperInterestRateModel;
    
    CErc20Delegator public cUSDC;
    CErc20Delegate public cUSDCDelegate;
    
    CErc20Delegator public cUni;
    CErc20Delegate public cUniDelegate;
    
    ERC20 public usdc;
    ERC20 public uni;
    address USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    address public admin = makeAddr("admin");

    function setUp() public virtual {
        vm.startPrank(admin);

        unitroller = new Unitroller();
        unitrollerProxy = Comptroller(address(unitroller));
        comptroller = new Comptroller();

        priceOracle = new SimplePriceOracle();
        whitePaperInterestRateModel = new WhitePaperInterestRateModel(0,0);
      
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        unitrollerProxy._setPriceOracle(priceOracle);
        // 基本設定：Close factor 設定為 50%
        unitrollerProxy._setCloseFactor(0.5 * 1e18);
        // 基本設定：Liquidation incentive 設為 8% (1.08 * 1e18)
        unitrollerProxy._setLiquidationIncentive(1.08 * 1e18);

        // 基本設定：使用 USDC 以及 UNI 代幣來作為 token A 以及 Token B
        usdc = ERC20(USDC_ADDRESS);
        uni = ERC20(UNI_ADDRESS);
        // ------------------------------------------------------------------------------------
        // cUSDC
        cUSDCDelegate = new CErc20Delegate();      
        cUSDC = new CErc20Delegator(
            address(cUSDC),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1e6, // initialExchangeRateMantissa_ 
            "cUSDC",
            "cUSDC",
            18,  // decimals_
            payable(admin),
            address(cUSDCDelegate),
            new bytes(0x00)
        );

        // 基本設定：cERC20 的 decimals 皆為 18，初始 exchangeRate 為 1:1
        // initialExchangeRateMantissa_ = 10^(18 - cToken.decimals() + underlyingToken.decimals())
        // = 10^(18 - 18 + 6) = 10^6
        
        cUSDC._setImplementation(address(cUSDCDelegate), false, new bytes(0x00));
        cUSDC._setReserveFactor(0);

        // ------------------------------------------------------------------------------------
        // cUSDC
        cUniDelegate = new CErc20Delegate();      
        cUni = new CErc20Delegator(
            address(cUni),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1e6, // initialExchangeRateMantissa_ 
            "cUni",
            "cUni",
            18,  // decimals_
            payable(admin),
            address(cUniDelegate),
            new bytes(0x00)
        );

        cUni._setImplementation(address(cUniDelegate), false, new bytes(0x00));
        cUni._setReserveFactor(0);

        // ------------------------------------------------------------------------------------
        // 基本設定：在 Oracle 中設定 USDC 的價格為 $1，UNI 的價格為 $5
        // 美元 scale 成合約使用的尺度
        //cUSDC.decimal // 6 -> 18 + 18 - 6 = 30  -> 1 * 10^30
        //cUni.decimal // 18 -> 18 + 18 - 18 =1 8 -> 5 * 10^18
        priceOracle.setUnderlyingPrice(CToken(address(cUSDC)), 1e30);
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 5e18);

        unitrollerProxy._supportMarket(CToken(address(cUSDC)));
        unitrollerProxy._supportMarket(CToken(address(cUni)));
        
        // 基本設定：設定 UNI 的 collateral factor 為 50%
        // 注意：先設定 OraclePrice 再設定 CollateralFactor
        unitrollerProxy._setCollateralFactor(CToken(address(cUSDC)), 0.5 * 1e18);

        vm.stopPrank();
    }
}
