// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

interface IPool {
    struct PoolDetail {
        uint40 timeStart;
        uint40 timeEnd;
        address poolAdmin;
        uint16 totalWinners;
        string poolName;
        uint256 depositAmountPerPerson;
        uint256 amountPerWinner;
    }

    struct PoolBalance {
        uint256 totalDeposits; // total deposit amount (won't reduce, for record)
        uint256 feesAccumulated;
        uint256 feesCollected;
        uint256 balance; // real current balance of pool
        uint256 sponsored; // extra balance from sponsor or participants
    }

    struct ParticipantDetail {
        uint256 deposit; // used for record
        uint256 feesCharged;
        uint120 participantIndex; // store index for easy removal
        uint120 joinedPoolsIndex; // store index for easy removal
        bool refunded;
    }

    struct WinnerDetail {
        uint256 amountWon;
        uint256 amountClaimed;
        uint40 timeWon;
    }

    // ----------------------------------------------------------------------------
    // Participant Functions
    // ----------------------------------------------------------------------------
    function deposit(uint256 poolId, uint256 amount) external returns (bool);
    function claimWinnings(uint256[] calldata poolIds, address[] calldata _winners) external;
    function claimWinning(uint256 poolId, address winner) external;

    // ----------------------------------------------------------------------------
    // Sponsor Functions
    // ----------------------------------------------------------------------------
    function sponsor(uint256 poolId, uint256 amount, string calldata oneTimeShortMessage) external;

    // ----------------------------------------------------------------------------
    // Host Functions
    // ----------------------------------------------------------------------------
    function createPool(
        uint40 timeStart,
        uint40 timeEnd,
        string calldata poolName,
        uint256 depositAmountPerPerson,
        address token,
        uint16 totalWinners,
        uint256 amountPerWinner
    ) external returns (uint256);

    function setWinnersEvenly(uint256 poolId, address[] calldata _winners) external;
    function setWinners(uint256 poolId, address[] calldata _winners, uint256[] calldata amounts) external;
    function setWinner(uint256 poolId, address winner, uint256 amount) external;
    function collectRemainingBalance(uint256 poolId) external;

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------
    function getHost(uint256 poolId) external view returns (address);
    function getPoolName(uint256 poolId) external view returns (string memory);
    function getPoolStartTime(uint256 poolId) external view returns (uint40);
    function getPoolEndTime(uint256 poolId) external view returns (uint40);
    function getSponsors(uint256 poolId) external view returns (address[] memory);
    function getSponsorMessages(uint256 poolId) external view returns (string[] memory);
    function getPoolDetail(uint256 poolId) external view returns (PoolDetail memory);
    function getPoolDeposits(uint256 poolId) external view returns (uint256);
    function getPoolBalance(uint256 poolId) external view returns (uint256);
    function getPoolToken(uint256 poolId) external view returns (address);
    function getSponsorshipAmount(uint256 poolId) external view returns (uint256);
    function getParticipantDeposit(address participant, uint256 poolId) external view returns (uint256);
    function getParticipantIndex(address participant, uint256 poolId) external view returns (uint256);
    function getParticipantDetail(address participant, uint256 poolId) external view returns (ParticipantDetail memory);
    function getWinningAmount(uint256 poolId, address winner) external view returns (uint256);
    function getWinnerTimeWon(uint256 poolId, address winner) external view returns (uint40);
    function getWinnerAmountClaimed(uint256 poolId, address winner) external view returns (uint256);
    function getWinnerDetail(uint256 poolId, address winner) external view returns (WinnerDetail memory);
    function getPoolsCreatedBy(address host) external view returns (uint256[] memory);
    function getPoolsJoinedBy(address participant) external view returns (uint256[] memory);
    function getParticipants(uint256 poolId) external view returns (address[] memory);
    function getWinners(uint256 poolId) external view returns (address[] memory);
    function getClaimablePools(address winner) external view returns (uint256[] memory, bool[] memory);
    function getWinnersDetails(uint256 poolId) external view returns (address[] memory, WinnerDetail[] memory);
    function getAllPoolInfo(uint256 poolId) external view returns (
        PoolDetail memory _poolDetail,
        PoolBalance memory _poolBalance,
        address _poolToken,
        address[] memory _participants,
        address[] memory _winners
    );

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(IERC20 token, uint256 amount) external;
}
