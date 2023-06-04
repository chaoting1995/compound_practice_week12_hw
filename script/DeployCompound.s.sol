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

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
  
        vm.stopBroadcast();
    }
}