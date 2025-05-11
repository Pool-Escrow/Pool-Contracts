// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";
import {IERC20} from "../src/interface/IERC20.sol";

contract EmergencyTest is Test {
	Pool public pool;
    Droplet public token;
    Droplet public token2;
    address public host;
    address public alice;
    address public bob;
    uint256 public amountToDeposit;
    uint256 public amountToDeposit2;
    uint256 public poolId;
    uint256 public poolId2;

    modifier turnOffGasMetering() {
        vm.pauseGasMetering();
        _;
        vm.resumeGasMetering();
    }    

    function setUp() public {
        pool = new Pool();
        token = new Droplet();
        token2 = new Droplet();
        host = vm.addr(1);
        alice = vm.addr(2);
        bob = vm.addr(3);
        pool.grantRole(pool.ADMIN_ROLE(), host);
    }

    function test_emergencyWithdraw() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        uint256 startingBalance = token.balanceOf(host);
        pool.pause();
        pool.emergencyWithdraw(IERC20(address(token)), pool.getPoolBalance(poolId));
        uint256 endingBalance = token.balanceOf(host);

        assertEq(endingBalance - startingBalance, amountToDeposit);
        assertEq(token.balanceOf(address(pool)), 0);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_poolStarted() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        vm.warp(block.timestamp + 10 days); // After pool start time
        uint256 startingBalance = token.balanceOf(host);
        pool.pause();
        pool.emergencyWithdraw(IERC20(address(token)), pool.getPoolBalance(poolId));
        uint256 endingBalance = token.balanceOf(host);

        assertEq(endingBalance - startingBalance, amountToDeposit);
        assertEq(token.balanceOf(address(pool)), 0);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_poolEnded() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        uint256 startingBalance = token.balanceOf(host);
        pool.pause();
        pool.emergencyWithdraw(IERC20(address(token)), pool.getPoolBalance(poolId));
        uint256 endingBalance = token.balanceOf(host);

        assertEq(endingBalance - startingBalance, amountToDeposit);
        assertEq(token.balanceOf(address(pool)), 0);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_multiPool() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();
        helper_createSecondPool();
        vm.warp(block.timestamp + 1 seconds);
        helper_depositSecond();

        vm.startPrank(host);
        uint256 startingBalance = token.balanceOf(host);
        pool.pause();
        uint256 toWithdraw = pool.getPoolBalance(poolId) + pool.getPoolBalance(poolId2);
        pool.emergencyWithdraw(IERC20(address(token)), toWithdraw);
        uint256 endingBalance = token.balanceOf(host);

        assertEq(endingBalance - startingBalance, amountToDeposit * 2);
        assertEq(token.balanceOf(address(pool)), 0);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_multiToken() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();
        helper_createPool2();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit2();

        vm.startPrank(host);
        uint256 startingBalance = token.balanceOf(host);
        uint256 startingBalance2 = token2.balanceOf(host);
        pool.pause();
        pool.emergencyWithdraw(IERC20(address(token)), pool.getPoolBalance(poolId));
        pool.emergencyWithdraw(IERC20(address(token2)), pool.getPoolBalance(poolId2));
        uint256 endingBalance = token.balanceOf(host);
        uint256 endingBalance2 = token2.balanceOf(host);

        assertEq(endingBalance - startingBalance, amountToDeposit);
        assertEq(endingBalance2 - startingBalance2, amountToDeposit);
        assertEq(token.balanceOf(address(pool)), 0);
        assertEq(token2.balanceOf(address(pool)), 0);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_notPaused() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        uint256 balance = pool.getPoolBalance(poolId);
        address tokenAddress = address(token);
        vm.expectRevert();
        pool.emergencyWithdraw(IERC20(tokenAddress), balance);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_nonAdmin() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        pool.pause();
        vm.startPrank(alice);
        uint256 balance = pool.getPoolBalance(poolId);
        address tokenAddress = address(token);
        vm.expectRevert();
        pool.emergencyWithdraw(IERC20(tokenAddress), balance);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------------
    // Helper Functions
    // ----------------------------------------------------------------------------

    function helper_createPool() private turnOffGasMetering {
        // Warp to random time
        vm.warp(1713935623);

        // Create a pool
        vm.startPrank(host);
        amountToDeposit = 100e18;
        poolId = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            amountToDeposit,
            address(token),
            2,  // totalWinners
            50e18  // amountPerWinner
        );
    }

    function helper_createSecondPool() private turnOffGasMetering {
        // Create a second pool
        // Alice create pool
        vm.startPrank(alice);
        poolId2 = pool.createPool(
            uint40(block.timestamp), 
            uint40(block.timestamp + 10 days), 
            "New", 
            amountToDeposit, 
            address(token),
            2,  // totalWinners
            50e18  // amountPerWinner
        );
    }

    function helper_createPool2() private turnOffGasMetering {
        // Warp to random time
        vm.warp(1713935623);

        // Create a pool
        vm.startPrank(host);
        amountToDeposit2 = 123e18;
        poolId2 = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "Second Pool",
            amountToDeposit,
            address(token2),
            2,  // totalWinners
            50e18  // amountPerWinner
        );
    }

    function helper_deposit() private turnOffGasMetering {
        // Deposit to the pool
        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId, amountToDeposit);
    }

    function helper_depositSecond() private turnOffGasMetering {
        // Deposit to the pool
        token.mint(bob, amountToDeposit);
        vm.startPrank(bob);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId2, amountToDeposit);
    }

    function helper_deposit2() private turnOffGasMetering {
        // Deposit to the pool
        token2.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token2.approve(address(pool), amountToDeposit);
        pool.deposit(poolId2, amountToDeposit);
    }
}