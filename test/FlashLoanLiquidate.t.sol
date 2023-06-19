// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { CTokenInterface } from "compound-protocol/contracts/CTokenInterfaces.sol";

import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";

import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";

import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";

import {
  IFlashLoanSimpleReceiver,
  IPoolAddressesProvider,
  IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

import { CompoundSetup } from "./helper/CompoundSetup.t.sol";
import { FlashLoanLiquidate } from "../src/FlashLoanLiquidate.sol";

contract TestFlashLoanLiquidate is CompoundSetup {

    address user1 = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    FlashLoanLiquidate public flashLoanLiquidate;

    function setUp() public override {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        
        // 基本設定：Fork Ethereum mainnet at block 17465000
        vm.createSelectFork(rpc, 17465000);
        super.setUp();

        vm.startPrank(admin);
        //init FlashLoanLiquidate
        flashLoanLiquidate = new FlashLoanLiquidate();

        //admin should provide the liquidate for USDC that user can borrow the USDC with UNI
        uint usdcAmount = 10000e18;
        deal(address(usdc), admin, usdcAmount);
        usdc.approve(address(cUSDC),usdcAmount);
        cUSDC.mint(usdcAmount);

        //deal 1000 uni token for user1 to borrow 2500 usdc (50% collateral factor)
        deal(address(uni), user1, 1000e18);
        vm.stopPrank();
    }

    function test_user_borrow_usdc() public {
        vm.startPrank(user1);

        //mint 1000 uni token to cUni and borrow the USDC
        uint mintAmount = 1000e18;
        uni.approve(address(cUni),mintAmount);
        cUni.mint(mintAmount);

        //enter market for cUni
        //用 1000 UNI 去借 2500 USDC
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cUni);
        unitrollerProxy.enterMarkets(cTokenAddr);
        cUSDC.borrow(2500e6);
        vm.stopPrank();

        assertEq(2500e6, IERC20(usdc).balanceOf(user1));
    }    

    function test_flashloan_for_liquidate_user1_flashLoanLiquidate() public {
        //與上一測試項目相同，先讓 User1 借錢
        vm.startPrank(user1);
        uint mintAmount = 1000e18;
        uni.approve(address(cUni),mintAmount);
        cUni.mint(mintAmount);
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cUni);
        unitrollerProxy.enterMarkets(cTokenAddr);
        cUSDC.borrow(2500e6);
        vm.stopPrank();

        //調整 UNI 價格為 4，造成 user1 產生 shortfall
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 4e18);
        vm.stopPrank();

        //讓 Liquidator 清算 user1 (aave 借款)
        vm.startPrank(liquidator);
        flashLoanLiquidate.execute(
          liquidator,
          user1,
          UNI_ADDRESS,
          USDC_ADDRESS,
          usdc,
          uni,
          unitrollerProxy,
          cUSDCDelegate,
          cUSDC,
          cUniDelegate,
          cUni
        );
        vm.stopPrank();
        console.log(IERC20(USDC_ADDRESS).balanceOf(address(flashLoanLiquidate)));
        assertGt(IERC20(USDC_ADDRESS).balanceOf(address(flashLoanLiquidate)), 63e6);
    }    

    function test_flashloan_for_liquidate_user1_pure() public {
        //與上一測試項目相同，先讓 User1 借錢
        vm.startPrank(user1);
        uint mintAmount = 1000e18;
        uni.approve(address(cUni),mintAmount);
        cUni.mint(mintAmount);
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cUni);
        unitrollerProxy.enterMarkets(cTokenAddr);
        cUSDC.borrow(2500e6);
        vm.stopPrank();

        //調整 UNI 價格為 4，造成 user1 產生 shortfall
        vm.startPrank(admin);
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 4e18);
        vm.stopPrank();

        //純粹打錢給 Liquidator，測試清算是否成功，因此最終結果會少了 flashload 的借款續費用
        deal(address(usdc),liquidator,1250e6);

        uint liquidateAmount = 1250e6;
        //讓 Liquidator 清算 user1
        vm.startPrank(liquidator);
        IERC20(usdc).approve(address(cUSDC), liquidateAmount);
        (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(address(user1));
        //可被清算
        if (error == 0 && liquidity == 0 && shortfall>0)
        {
            CTokenInterface cUniToken = CTokenInterface(address(cUni));
            uint repayAmount = liquidateAmount;
            cUSDC.liquidateBorrow(user1, repayAmount, cUniToken);
        }
        //redeem cUni to UNI
        uint cUniBalanceOfLiquidator = cUni.balanceOf(liquidator);
        cUni.redeem(cUniBalanceOfLiquidator);
        //取得 328.05 UNI

        //approve uni to router for safe transferFrom
        address uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        uni.approve(uniV3Router, cUniBalanceOfLiquidator);
        ISwapRouter.ExactInputSingleParams memory swapParams =
          ISwapRouter.ExactInputSingleParams({
            tokenIn: UNI_ADDRESS,
            tokenOut: USDC_ADDRESS,
            fee: 3000, // 0.3%
            recipient: address(liquidator),
            deadline: block.timestamp,
            amountIn: cUniBalanceOfLiquidator,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
          });

        ISwapRouter(uniV3Router).exactInputSingle(swapParams);
        uint256 liquidatorProfit = IERC20(USDC_ADDRESS).balanceOf(address(liquidator)) - 1250e6;
        console.log(liquidatorProfit);
        vm.stopPrank();

        assertGt(liquidatorProfit, 63e6);
    }    
}