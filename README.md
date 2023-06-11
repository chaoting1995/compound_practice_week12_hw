# compound_practice_week12_hw
請賞析 [Compound](https://docs.compound.finance/v2/) 的合約，並依序實作以下

## 1. 撰寫一個 Foundry 的 Script，該 Script 要能夠部署
- 一個 CErc20Delegator(`CErc20Delegator.sol`，以下簡稱 cERC20)
- 一個 Unitroller(`Unitroller.sol`)
- 以及他們的 Implementation 合約
- 和合約初始化時相關必要合約

請遵循以下細節：

- cERC20 的 decimals 皆為 18
- 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
- 使用 `SimplePriceOracle` 作為 Oracle
- 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
- 初始 exchangeRate 為 1:1

### run project

#### Step1: setting `.env.example`
```
PRIVATE_KEY=
MY_ADDRESS=
GOERLI_RPC_URL=https://goerli.infura.io/v3/ee11e79fa3d94cac84f2325726a61ba0
ETHERSCAN_API_KEY=48SYKYBYUABD99UDSEWGS3X3U62QXRJ3WX
```
#### Step2: install
```
forge install
```
#### Step3: run script
```bash
# 確保在環境中設置了環境變量
source .env

# 執行部署腳本
forge script script/DeployCompound.s.sol:DeployCompound --rpc-url ${GOERLI_RPC_URL} --broadcast --verify
```
