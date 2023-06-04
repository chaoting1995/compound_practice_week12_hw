// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
// import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

contract DeployCompound is Script {
    function setUp() public {

    }

// 1. 撰寫一個 Foundry 的 Script，該 Script 要能夠部署
//     - 一個 CErc20Delegator(`CErc20Delegator.sol`，以下簡稱 cERC20)
//     - 一個 Unitroller(`Unitroller.sol`)
//     - 以及他們的 Implementation 合約
//     - 和合約初始化時相關必要合約
    
//     請遵循以下細節：
    
//     - cERC20 的 decimals 皆為 18
//     - 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
//     - 使用 `SimplePriceOracle` 作為 Oracle
//     - 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
//     - 初始 exchangeRate 為 1:1

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
  
        vm.stopBroadcast();
    }
}