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

// 部署 CErc20Delegator(`CErc20Delegator.sol`，以下簡稱 cERC20)
// 部署 CErc20Delegator 的 Implementation 合約
// 部署 Unitroller(`Unitroller.sol`)
// 部署 Unitroller 的 Implementation 合約
// 部署合約初始化時相關必要合約

// 請遵循以下細節：
    
// cERC20 的 decimals 皆為 18
// 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
// 使用 `SimplePriceOracle` 作為 Oracle
// 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
// 初始 exchangeRate 為 1:1

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
  
        address admin = vm.envAddress("MY_ADDRESS");
        vm.startBroadcast(key);

        // 部署 Unitroller
        Unitroller unitroller = new Unitroller();
        Comptroller unitrollerProxy = Comptroller(address(unitroller));
        Comptroller comptroller = new Comptroller();

        // 部署 Unitroller 的 Implementation 合約
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        // 設定清算係數 10%
        unitrollerProxy._setCloseFactor(0.1 * 1e18);
        // 設定清算獎勵 1.05
        unitrollerProxy._setLiquidationIncentive(1.05 * 1e18);
        // 使用 `SimplePriceOracle` 作為 Oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        unitrollerProxy._setPriceOracle(priceOracle);

        // 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
        WhitePaperInterestRateModel whitePaperInterestRateModel = new WhitePaperInterestRateModel(0,0);

        // 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
        ERC20 testCoin = new ERC20("Test Coin", "TEST");

        // prepare token implementation, CErc20Delegate
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        
        // 部署 CErc20Delegator
        // 部署 CErc20Delegator 的 Implementation 合約
        CErc20Delegator cTestCoin = new CErc20Delegator(
            address(testCoin),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1, // decimals 都是 18, rate 10 ** 18 / 10 ** 18
            "Compound TestCoin",
            "cTestCoin",
            18,
            payable(admin),
            address(cErc20Delegate),
            new bytes(0x01)
        );

        cTestCoin._setReserveFactor(0.1 * 1e18);

        // cTestCoin 加到 unitroller markets map
        unitrollerProxy._supportMarket(CToken(address(cTestCoin)));

        // Collateral Factor 設為 80%
        unitrollerProxy._setCollateralFactor(CToken(address(cTestCoin)), 0.8 * 1e18);
        // 初始 exchangeRate 為 1:1
        priceOracle.setUnderlyingPrice(CToken(address(cTestCoin)), 1e18);

        vm.stopBroadcast();
    }
}