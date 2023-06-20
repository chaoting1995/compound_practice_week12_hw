// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

import { CToken } from "compound-protocol/contracts/CToken.sol";
import { CTokenInterface } from "compound-protocol/contracts/CTokenInterfaces.sol";
 
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import { CompoundSetup } from "./helper/CompoundSetup.t.sol";
import { FlashLoanLiquidate } from "../src/FlashLoanLiquidate.sol";

contract TestFlashLoanLiquidate is CompoundSetup {

    address user1 = makeAddr("user");
    address user2 = makeAddr("user2");
    FlashLoanLiquidate public flashLoanLiquidate;

    function setUp() public override {        
        // 基本設定：Fork Ethereum mainnet at block 17465000
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 17465000);

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

    function test_aave_flashloan_liquidate_user1() public {
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
        vm.startPrank(user2);
        flashLoanLiquidate.execute(
          user2,
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
}