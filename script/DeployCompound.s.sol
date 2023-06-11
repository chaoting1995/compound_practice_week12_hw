// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
import "compound-protocol/contracts/ComptrollerInterface.sol";

import "compound-protocol/contracts/CErc20Delegate.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";

import "compound-protocol/contracts/InterestRateModel.sol";
import "compound-protocol/contracts/SimplePriceOracle.sol";
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";

import "openzeppelin/token/ERC20/ERC20.sol";

contract DeployCompound is Script {
    ERC20 public testCoin;
    CErc20Delegator public cTestCoin;
    CErc20Delegate public cErc20Delegate;
    WhitePaperInterestRateModel	public whitePaper;
    Unitroller public unitroller;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    SimplePriceOracle public priceOracle;

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
    
    function setup() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        // 部署 Unitroller
        unitroller = new Unitroller();
        // 用 實作合約 Comptroller 的 interface 封裝 代理合約 unitroller
        unitrollerProxy = Comptroller(address(unitroller));
        // 部署 Unitroller 的 Implementation 合約
        comptroller = new Comptroller();
        // 部署 SimplePriceOracle // 使用 `SimplePriceOracle` 作為 Oracle
        priceOracle = new SimplePriceOracle();

        // 設：unitroller 的變量「待定實作合約 pendingComptrollerImplementation」 -> 為：實作合約 comptroller
        unitroller._setPendingImplementation(address(comptroller));
        // 設：unitroller 的變量「待定實作合約 pendingComptrollerImplementation」 -> 為：unitroller 的 變量「實作合約comptrollerImplementation」
        comptroller._become(unitroller);

        // 設定 cToken 的清算係數 Close Factor (按 1e18 縮放)
        unitrollerProxy._setCloseFactor(0.5 * 1e18);
        // 設定 cToken 的清算獎勵 Liquidation Incentive (按 1e18 縮放)
        unitrollerProxy._setLiquidationIncentive(1.05 * 1e18);
        // 設定 cToken 的美元兌換匯率 Oracle Price (USD/cToken)
        unitrollerProxy._setPriceOracle(priceOracle);

        // -------------------------------------------------------------------------------------------
        // CErc20Delegator 部署合約初始化時相關必要合約

        // 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
        testCoin = new ERC20("Test Coin", "TEST");

        // 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
        WhitePaperInterestRateModel whitePaperInterestRateModel = new WhitePaperInterestRateModel(0,0);
        
        // 部署 CErc20Delegator 的 Implementation 合約 CErc20Delegate
        cErc20Delegate = new CErc20Delegate();
        // -------------------------------------------------------------------------------------------
        // 部署 CErc20Delegator
        cTestCoin = new CErc20Delegator(
            address(testCoin),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1e18, // 依照作業條件，放大倍率調整為：scaled by  1 * 10^(18 - 18 + 18) = 10^18
            "Compound TestCoin",
            "cTestCoin",
            18, // cERC20 的 decimals 皆為 18
            payable(vm.envAddress("MY_ADDRESS")),
            address(cErc20Delegate),
            new bytes(0x0)
        );
        
        // -------------------------------------------------------------------------------------------
        // 設定 cToken 的儲備係數 Reserve Factor
        cTestCoin._setReserveFactor(0.1 * 1e18);

        // 把 cToken 加到 unitroller markets map
        unitrollerProxy._supportMarket(CToken(address(cTestCoin)));
        
        // 設定 cToken 的抵押係數 Collateral Factor
        unitrollerProxy._setCollateralFactor(CToken(address(cTestCoin)), 0.8 * 1e18);

        // 設定 underlying token 的價格初始 // exchangeRate 為 1:1，也就是等同於 cToken
        priceOracle.setUnderlyingPrice(CToken(address(cTestCoin)), 1e18);

        vm.stopBroadcast();
    }

    function run() public {}
}