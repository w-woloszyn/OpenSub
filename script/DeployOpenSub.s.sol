// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {OpenSub} from "../src/OpenSub.sol";

contract DeployOpenSub is Script {
    function run() external returns (OpenSub deployed) {
        vm.startBroadcast();
        deployed = new OpenSub();
        vm.stopBroadcast();
    }
}
