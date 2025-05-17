// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PoolScript is Script {
    Pool public pool;
    Droplet public token;
    IERC20 public usdc;

    // Token addresses for different networks
    address constant USDC_BASE_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            revert("Please set the PRIVATE_KEY environment variable");
        }

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the Pool contract
        pool = new Pool();

        // Get the chain ID
        uint256 chainId = block.chainid;

        // Handle token setup based on network
        if (chainId == 8453) { // Base Mainnet
            usdc = IERC20(USDC_BASE_MAINNET);
        } else { // Sepolia or Local
            // Deploy a mock token for testing
            token = new Droplet();
            usdc = IERC20(address(token));
            
            // Mint some tokens to the deployer for testing
            token.mint(vm.addr(deployerPrivateKey), 1000000e18);
        }

        // Create the pool
        pool.createPool(
            uint40(block.timestamp + 2 days),
            uint40(block.timestamp + 2 days + 6 hours),
            "Test pool",
            1000,
            address(usdc),
            1,
            1000
        );

        vm.stopBroadcast();
    }

    function run_withMock() public {
        vm.startBroadcast(msg.sender);
        pool = new Pool();
        token = new Droplet();
        vm.stopBroadcast();
    }

    // function run_withSetup() public {
    //     vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    //     address signer = vm.addr(vm.envUint("PRIVATE_KEY"));
    //     pool = new Pool();
    //     token = Droplet(0xfD2Ec58cE4c87b253567Ff98ce2778de6AF0101b);

    //     uint256 amount = 20e18;
    //     if (token.balanceOf(signer) == 0) {
    //         token.mint(signer, 1000e18);
    //     }
    //     pool.grantRole(pool.WHITELISTED_HOST(), signer);
    //     uint256 poolId = pool.createPool(
    //         uint40(block.timestamp + 2 days),
    //         uint40(block.timestamp + 2 days + 6 hours),
    //         "Test pool",
    //         amount,
    //         3000,
    //         address(0xfD2Ec58cE4c87b253567Ff98ce2778de6AF0101b)
    //     );
    //     pool.enableDeposit(poolId);
    //     token.approve(address(pool), amount);
    //     pool.deposit(poolId, amount);
    //     vm.stopBroadcast();
    // }
}
