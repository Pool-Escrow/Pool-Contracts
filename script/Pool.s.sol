// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";

contract PoolScript is Script {
    Pool public pool;
    Droplet public token;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        vm.stopBroadcast();
    }

    function run_withMock() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        pool = new Pool();
        token = new Droplet();
        vm.stopBroadcast();
    }

    function run_withSetup() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address signer = vm.addr(vm.envUint("PRIVATE_KEY"));
        pool = Pool(0x7b8C409C603E7857314d94DC11f3C8F928421234);
        token = Droplet(0x203f3C5EbdbdBD03e19CF1C1378D3A4fCB9358d4);

        uint256 amount = 20e18;
        if (token.balanceOf(signer) == 0) {
            token.mint(signer, 1000e18);
        }
        pool.grantRole(pool.WHITELISTED_HOST(), signer);
        uint256 poolId = pool.createPool(
            uint40(block.timestamp + 2 days),
            uint40(block.timestamp + 2 days + 6 hours),
            "Test pool",
            amount,
            address(token)
        );
        pool.enableDeposit(poolId);
        token.approve(address(pool), amount);
        pool.deposit(poolId, amount);
        vm.stopBroadcast();
    }
}
