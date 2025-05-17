// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Droplet} from "../src/mock/MockERC20.sol";

contract DropletScript is Script {
    Droplet public token;
    
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            revert("Please set the PRIVATE_KEY environment variable");
        }

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the Droplet token
        token = new Droplet();
        
        // Initial mint to deployer
        token.mint(vm.addr(deployerPrivateKey), 1000000e18);

        vm.stopBroadcast();
    }
} 