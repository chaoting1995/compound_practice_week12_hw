// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {
  IFlashLoanSimpleReceiver,
  IPoolAddressesProvider,
  IPool
} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";

import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { CTokenInterface } from "compound-protocol/contracts/CTokenInterfaces.sol";


import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// TODO: Inherit IFlashLoanSimpleReceiver
contract FlashLoanLiquidate is IFlashLoanSimpleReceiver {
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
