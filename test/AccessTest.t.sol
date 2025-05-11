// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import {IERC20} from "../src/interface/IERC20.sol";

contract AccessTest is Test {
    Pool public pool;
    Droplet public token;
    address public host;
    address public alice;
    uint256 public poolId;

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        host = vm.addr(1);
        alice = vm.addr(2);
        pool.grantRole(pool.ADMIN_ROLE(), host);
        vm.warp(1713935623);

        // Create a pool
        vm.startPrank(host);
        poolId = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            address(token),
            2,
            50e18
        );

        // Warp to after pool start time
        vm.warp(block.timestamp + 10 days + 1 seconds);

        // Deposit to the pool
        uint256 amount = 100e18;
        token.mint(alice, amount);
        vm.startPrank(alice);
        token.approve(address(pool), amount);
        pool.deposit(poolId, amount);
    }

    function test_pause() external {
        vm.startPrank(host);
        pool.pause();
        bool paused = pool.paused();
        assertEq(paused, true);
        vm.stopPrank();
    }

    function test_pause_tryCreatePool() external {
        vm.startPrank(host);
        pool.pause();

        vm.expectRevert();
        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            address(token),
            2,
            50e18
        );
        vm.stopPrank();
    }

    function test_pause_tryDeposit() external {
        vm.startPrank(host);
        pool.pause();

        uint256 amount = 100e18;
        address bob = vm.addr(0xB0B);
        token.mint(bob, amount);
        vm.startPrank(bob);
        token.approve(address(pool), amount);

        vm.expectRevert();
        pool.deposit(poolId, amount);
        vm.stopPrank();
    }

    function test_pause_nonAdmin() external {
        vm.startPrank(alice);
        vm.expectRevert();
        pool.pause();
        vm.stopPrank();
    }

    function test_unpause() external {
        // Setup
        vm.startPrank(host);
        pool.pause();

        // Unpause contract
        pool.unpause();
        bool paused = pool.paused();
        assertEq(paused, false);
        vm.stopPrank();
    }

    function test_unpause_nonAdmin() external {
        // Setup
        vm.startPrank(host);
        pool.pause();

        // Should fail
        vm.startPrank(alice);
        vm.expectRevert();
        pool.unpause();
        vm.stopPrank();
    }

    function test_onlyHost_modifier() external {
        vm.startPrank(alice);
        vm.warp(block.timestamp + 11 days); // After pool end time
        vm.expectRevert();
        pool.setWinner(poolId, alice, 50e18);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_nonAdmin() external {
        vm.startPrank(address(this));
        pool.pause();
        vm.startPrank(alice);
        vm.expectRevert();
        pool.emergencyWithdraw(IERC20(address(token)), 100e18);
        vm.stopPrank();
    }
}
