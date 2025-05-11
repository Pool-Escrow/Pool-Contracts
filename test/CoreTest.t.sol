// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/Pool.sol";
import {Droplet} from "../src/mock/MockERC20.sol";

contract CoreTest is Test {
    Pool public pool;
    Droplet public token;
    address public host;
    address public alice;
    address public bob;
    uint256 public amountToDeposit;
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
        host = vm.addr(1);
        alice = vm.addr(2);
        bob = vm.addr(3);
    }

    function test_createPool() public {
        vm.startPrank(host);
        poolId = pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            address(token),
            4, // totalWinners
            25e18 // amountPerWinner
        );

        assertEq(pool.getHost(poolId), host);
        assertEq(pool.getPoolName(poolId), "PoolParty");
        assertEq(pool.getPoolStartTime(poolId), block.timestamp + 10 days);
        assertEq(pool.getPoolEndTime(poolId), block.timestamp + 11 days);
        assertEq(pool.getPoolToken(poolId), address(token));
        vm.stopPrank();
    }

    function test_createPool_invalidTiming() public {
        vm.startPrank(host);
        vm.expectRevert("Invalid timing");
        pool.createPool(
            uint40(block.timestamp + 11 days), // start after end
            uint40(block.timestamp + 10 days),
            "PoolParty",
            100e18,
            address(token),
            4,
            25e18
        );
        vm.stopPrank();
    }

    function test_createPool_invalidToken() public {
        vm.startPrank(host);
        vm.expectRevert("Token not contract");
        pool.createPool(
            uint40(block.timestamp + 10 days),
            uint40(block.timestamp + 11 days),
            "PoolParty",
            100e18,
            address(0), // invalid token
            4,
            25e18
        );
        vm.stopPrank();
    }

    function test_deposit() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        assertEq(pool.getParticipantDeposit(alice, poolId), amountToDeposit);
        assertTrue(pool.isParticipant(alice, poolId));
        vm.stopPrank();
    }

    function test_deposit_extraAmount() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);

        // Deposit to the pool
        uint256 extraAmount = amountToDeposit + 50e18;
        token.mint(alice, extraAmount);
        vm.startPrank(alice);
        token.approve(address(pool), extraAmount);
        pool.deposit(poolId, extraAmount);
        vm.stopPrank();

        assertEq(pool.getParticipantDeposit(alice, poolId), amountToDeposit);
        assertEq(pool.getSponsorshipAmount(poolId), 50e18);
        vm.stopPrank();
    }

    function test_deposit_insufficientAmount() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);

        uint256 insufficientAmount = amountToDeposit - 1;
        token.mint(alice, insufficientAmount);
        vm.startPrank(alice);
        token.approve(address(pool), insufficientAmount);
        vm.expectRevert("Insufficient amount");
        pool.deposit(poolId, insufficientAmount);
        vm.stopPrank();
    }

    function test_deposit_alreadyParticipant() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        vm.expectRevert("Already in pool");
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function test_deposit_afterStartPool() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days); // Exactly at pool start time

        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        vm.expectRevert("Pool not started");
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function test_deposit_afterEndPool() external {
        helper_createPool();
        vm.warp(block.timestamp + 11 days + 1 seconds); // After pool end time

        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        vm.expectRevert("Pool ended");
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function test_setWinner() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinner(poolId, alice, winnings);
        uint256 res = pool.getWinningAmount(poolId, alice);

        assertEq(res, winnings);
        vm.stopPrank();
    }

    function test_setWinner_exceedPoolBalance() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winnings = 1000e18;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time

        // Expect revert because winnings exceed pool balance
        vm.expectRevert("Not enough balance");
        pool.setWinner(poolId, alice, winnings);

        vm.stopPrank();
    }

    function test_setWinner_sameWinnerMultipleTimes() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinner(poolId, alice, winnings);
        pool.setWinner(poolId, alice, winnings);
        uint256 res = pool.getWinningAmount(poolId, alice);

        assertEq(res, winnings * 2);
        vm.stopPrank();
    }

    function test_setWinnersMultiple_poolRemainingBalanceZero() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        // Setup
        uint256 winning = 125e18; // 5 deposits divided by 4 winners
        uint256[] memory winnings = new uint256[](4);
        address[] memory winners = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            winners[i] = vm.addr(i + 4);
            winnings[i] = winning;
            token.mint(winners[i], amountToDeposit);
            vm.startPrank(winners[i]);
            token.approve(address(pool), amountToDeposit);
            pool.deposit(poolId, amountToDeposit);
        }
        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinners(poolId, winners, winnings);
        uint256 res = pool.getPoolBalance(poolId);

        // Remaining balance should be 0
        assertEq(res, 0);
        vm.stopPrank();
    }

    function test_setWinner_participantNotDeposited() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winning = amountToDeposit;
        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time

        // Should fail because participant has not deposited
        vm.expectRevert("Not a participant");
        pool.setWinner(poolId, vm.addr(0xBEEF), winning);
        vm.stopPrank();
    }

    function test_setWinner_beforeEndTime() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winning = amountToDeposit;

        // Should fail because pool is not ended
        vm.startPrank(host);
        vm.expectRevert("Pool not ended");
        pool.setWinner(poolId, alice, winning);
        vm.stopPrank();
    }

    function test_claimWinnings() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        uint256 winnings = 23e18;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinner(poolId, alice, winnings);

        vm.startPrank(alice);
        pool.claimWinning(poolId, alice);
        uint256 res = token.balanceOf(alice);

        assertEq(res, winnings);
        vm.stopPrank();
    }

    function test_collectRemainingBalance() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        vm.warp(block.timestamp + 1 days + pool.TIME_DELAY()); // After pool end time + TIME_DELAY

        uint256 remainingBalance = pool.getPoolBalance(poolId);
        uint256 balanceBefore = token.balanceOf(host);
        pool.collectRemainingBalance(poolId);
        uint256 balanceAfter = token.balanceOf(host);

        assertEq(balanceAfter - balanceBefore, remainingBalance);
        assertEq(pool.getPoolBalance(poolId), 0);
        vm.stopPrank();
    }

    function test_collectRemainingBalance_beforeTimeDelay() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        vm.startPrank(host);
        vm.warp(block.timestamp + 1 days); // After pool end time but before TIME_DELAY

        vm.expectRevert("Pool not ended");
        pool.collectRemainingBalance(poolId);
        vm.stopPrank();
    }

    function test_getAllPoolInfo() external {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();

        // Use -vvvv to check returns
        pool.getAllPoolInfo(poolId);
    }

    function test_sponsor() external {
        helper_createPool();
        uint256 sponsorAmount = 50e18;
        string memory message = "Good luck!";

        token.mint(bob, sponsorAmount);
        vm.startPrank(bob);
        token.approve(address(pool), sponsorAmount);
        pool.sponsor(poolId, sponsorAmount, message);

        assertEq(pool.getSponsorshipAmount(poolId), sponsorAmount);
        assertEq(pool.getSponsors(poolId)[0], bob);
        assertEq(pool.getSponsorMessages(poolId)[0], message);
        vm.stopPrank();
    }

    function test_sponsor_poolNotCreated() external {
        uint256 sponsorAmount = 50e18;
        string memory message = "Good luck!";

        token.mint(bob, sponsorAmount);
        vm.startPrank(bob);
        token.approve(address(pool), sponsorAmount);

        vm.expectRevert("Pool not created");
        pool.sponsor(999, sponsorAmount, message);
        vm.stopPrank();
    }

    function test_sponsor_poolEnded() external {
        helper_createPool();
        uint256 sponsorAmount = 50e18;
        string memory message = "Good luck!";

        token.mint(bob, sponsorAmount);
        vm.startPrank(bob);
        token.approve(address(pool), sponsorAmount);
        vm.warp(block.timestamp + 11 days + 1 seconds); // After pool end time

        vm.expectRevert("Pool ended");
        pool.sponsor(poolId, sponsorAmount, message);
        vm.stopPrank();
    }

    function test_setWinners() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();
        helper_deposit_bob();

        address[] memory winners = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        winners[0] = alice;
        winners[1] = bob;
        amounts[0] = 60e18;
        amounts[1] = 40e18;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinners(poolId, winners, amounts);

        assertEq(pool.getWinningAmount(poolId, alice), 60e18);
        assertEq(pool.getWinningAmount(poolId, bob), 40e18);
        vm.stopPrank();
    }

    function test_setWinnersEvenly() public {
        helper_createPool();
        vm.warp(block.timestamp + 10 days + 1 seconds);
        helper_deposit();
        helper_deposit_bob();

        address[] memory winners = new address[](2);
        winners[0] = alice;
        winners[1] = bob;

        vm.startPrank(host);
        vm.warp(block.timestamp + 11 days); // After pool end time
        pool.setWinnersEvenly(poolId, winners);

        uint256 expectedAmount = pool.getPoolBalance(poolId) / 2;
        assertEq(pool.getWinningAmount(poolId, alice), expectedAmount);
        assertEq(pool.getWinningAmount(poolId, bob), expectedAmount);
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
            2,
            50e18
        );
        vm.stopPrank();
    }

    function helper_createSecondPool() private turnOffGasMetering {
        // Create a second pool
        vm.startPrank(host);
        poolId2 = pool.createPool(
            uint40(block.timestamp),
            uint40(block.timestamp + 10 days),
            "New",
            amountToDeposit,
            address(token),
            2,
            50e18
        );
        vm.stopPrank();
    }

    function helper_deposit() private turnOffGasMetering {
        // Deposit to the pool
        token.mint(alice, amountToDeposit);
        vm.startPrank(alice);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }

    function helper_deposit_bob() private turnOffGasMetering {
        // Deposit to the pool
        token.mint(bob, amountToDeposit);
        vm.startPrank(bob);
        token.approve(address(pool), amountToDeposit);
        pool.deposit(poolId, amountToDeposit);
        vm.stopPrank();
    }
}
