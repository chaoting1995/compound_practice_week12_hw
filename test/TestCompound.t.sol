// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC20 } from "compound-protocol/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "compound-protocol/contracts/token/ERC20/IERC20.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { CTokenInterface } from "compound-protocol/contracts/CTokenInterfaces.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";
import {
  IFlashLoanSimpleReceiver,
  IPoolAddressesProvider,
  IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import { CompoundSetup } from "./helper/CompoundSetup.t.sol";

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
  address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
  address uniV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

  //prepare callback struct for compound callback
  struct CallbackData {
      address liquidator;
      address borrower;
      address uniTokenAddress;
      address usdcTokenAddress;
      ERC20 usdcUnderLying;
      ERC20 uniUnderLying;
      Comptroller unitrollerProxy;
      CErc20Delegate cUSDCDelegate;
      CErc20Delegator cUSDC;
      CErc20Delegate cUniDelegate;
      CErc20Delegator cUni;
  }

  function execute(
    address _liquidator,
    address _borrower,
    address _uniTokenAddress,
    address _usdcTokenAddress,
    ERC20 _usdcUnderLying, 
    ERC20 _uniUnderLying, 
    Comptroller _unitrollerProxy, 
    CErc20Delegate _cUSDCDelegate,
    CErc20Delegator _cUSDC,
    CErc20Delegate _cUniDelegate,
    CErc20Delegator _cUni
   ) external {
      CallbackData memory callbackUsed = CallbackData({
          liquidator: _liquidator,
          borrower: _borrower,
          uniTokenAddress: _uniTokenAddress,
          usdcTokenAddress: _usdcTokenAddress,
          usdcUnderLying: _usdcUnderLying,
          uniUnderLying: _uniUnderLying,
          unitrollerProxy: _unitrollerProxy,
          cUSDCDelegate: _cUSDCDelegate,
          cUSDC: _cUSDC,
          cUniDelegate:_cUniDelegate,
          cUni:_cUni
      });
      //borrow 1250e6 and let flashloan contract callback to this contract
      POOL().flashLoanSimple(address(this),address(USDC),1250e6, abi.encode(callbackUsed) ,0);
  }

  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) override external returns (bool) {

      //decode the callbackdata
      CallbackData memory callBackData = abi.decode(params, (CallbackData));

      //need to approve cUSDC cerc20 contract to use our usdc for liquidation
      callBackData.usdcUnderLying.approve(address(callBackData.cUSDC), 1250e6);
      //check the account health for borrower
      (uint error, uint liquidity, uint shortfall) = callBackData.unitrollerProxy.getAccountLiquidity(address(callBackData.borrower));
      //we can liquidate this account if this condition is pass
      if (error == 0 && liquidity == 0 && shortfall>0)
      {
          CTokenInterface cUniToken = CTokenInterface(address(callBackData.cUni));
          uint repayAmount = 1250e6;
          callBackData.cUSDC.liquidateBorrow(callBackData.borrower, repayAmount, cUniToken);
      }
      //redeem cUni to UNI
      uint cUniBalanceOfLiquidator = callBackData.cUni.balanceOf(address(this));
      callBackData.cUni.redeem(cUniBalanceOfLiquidator);  
      //get 325.08 UNI 

      //approve uni to uniswap_router for safe transferFrom
      callBackData.uniUnderLying.approve(uniV3Router, cUniBalanceOfLiquidator);
      ISwapRouter.ExactInputSingleParams memory swapParams =
        ISwapRouter.ExactInputSingleParams({
          tokenIn: callBackData.uniTokenAddress,
          tokenOut: callBackData.usdcTokenAddress,
          fee: 3000, // 0.3%
          recipient: address(this),
          deadline: block.timestamp,
          amountIn: cUniBalanceOfLiquidator,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
          });

      ISwapRouter(uniV3Router).exactInputSingle(swapParams);
      //approve POOL() for ERC20 token to rapay the debt to flashloan contract
      IERC20(asset).approve(address(POOL()), 1250e6 + premium);
      return true;
  }

  function ADDRESSES_PROVIDER() public view override returns (IPoolAddressesProvider) {
    return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
  }

  function POOL() public view override returns (IPool) {
    return IPool(ADDRESSES_PROVIDER().getPool());
  }
}

contract AaveLiquidate is CompoundSetup{

    address user1 = makeAddr("user");
    address liquidator = makeAddr("liquidator");
    AaveFlashLoan public aave;

    function setUp() public override {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        
        // 基本設定：Fork Ethereum mainnet at block 17465000
        vm.createSelectFork(rpc, 17465000);
        super.setUp();

        vm.startPrank(admin);
        //init AaveFlashLoan
        aave = new AaveFlashLoan();

        //admin should provide the liquidate for USDC that user can borrow the USDC with UNI
        uint usdcAmount = 10000e18;
        deal(address(usdcUnderLying), admin, usdcAmount);
        usdcUnderLying.approve(address(cUSDC),usdcAmount);
        cUSDC.mint(usdcAmount);

        //deal 1000 uni token for user1 to borrow 2500 usdc (50% collateral factor)
        deal(address(uniUnderLying), user1, 1000e18);
        vm.stopPrank();
    }

    function test_user_borrow_usdc() public {
        vm.startPrank(user1);

        //mint 1000 uni token to cUni and borrow the USDC
        uint mintAmount = 1000e18;
        uniUnderLying.approve(address(cUni),mintAmount);
        cUni.mint(mintAmount);

        //enter market for cUni
        //用 1000 UNI 去借 2500 USDC
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cUni);
        unitrollerProxy.enterMarkets(cTokenAddr);
        cUSDC.borrow(2500e6);
        vm.stopPrank();

        assertEq(2500e6, IERC20(usdcUnderLying).balanceOf(user1));
    }    

    function test_flashloan_for_liquidate_user1_aave() public {
        //與上一測試項目相同，先讓 User1 借錢
        vm.startPrank(user1);
        uint mintAmount = 1000e18;
        uniUnderLying.approve(address(cUni),mintAmount);
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

        //讓 Liquidator 清算 user1 (Aave 借款)
        vm.startPrank(liquidator);
        aave.execute(
          liquidator,
          user1,
          uniTokenAddress,
          usdcTokenAddress,
          usdcUnderLying,
          uniUnderLying,
          unitrollerProxy,
          cUSDCDelegate,
          cUSDC,
          cUniDelegate,
          cUni
        );
        vm.stopPrank();
        console.log(IERC20(usdcTokenAddress).balanceOf(address(aave)));
        assertGt(IERC20(usdcTokenAddress).balanceOf(address(aave)), 63e6);
    }    

    function test_flashloan_for_liquidate_user1_pure() public {
        //與上一測試項目相同，先讓 User1 借錢
        vm.startPrank(user1);
        uint mintAmount = 1000e18;
        uniUnderLying.approve(address(cUni),mintAmount);
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
        deal(address(usdcUnderLying),liquidator,1250e6);

        uint liquidateAmount = 1250e6;
        //讓 Liquidator 清算 user1
        vm.startPrank(liquidator);
        IERC20(usdcUnderLying).approve(address(cUSDC), liquidateAmount);
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
        uniUnderLying.approve(uniV3Router, cUniBalanceOfLiquidator);
        ISwapRouter.ExactInputSingleParams memory swapParams =
          ISwapRouter.ExactInputSingleParams({
            tokenIn: uniTokenAddress,
            tokenOut: usdcTokenAddress,
            fee: 3000, // 0.3%
            recipient: address(liquidator),
            deadline: block.timestamp,
            amountIn: cUniBalanceOfLiquidator,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
          });

        ISwapRouter(uniV3Router).exactInputSingle(swapParams);
        uint256 liquidatorProfit = IERC20(usdcTokenAddress).balanceOf(address(liquidator)) - 1250e6;
        console.log(liquidatorProfit);
        vm.stopPrank();

        assertGt(liquidatorProfit, 63e6);

    }    
}