// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {IERC20} from "./IERC20.sol";

interface IPool {
    event PoolCreated(
        uint256 poolId,
        address indexed host,
        string poolName,
        uint256 depositAmountPerPerson,
        address indexed token
    );
    event PoolBalanceUpdated(uint256 poolId, uint256 balanceBefore, uint256 balanceAfter);
    event PoolStatusChanged(uint256 poolId, IPool.POOLSTATUS status);
    event Refund(uint256 poolId, address indexed participant, uint256 amount);
    event Deposit(uint256 poolId, address indexed participant, uint256 amount);
    event ExtraDeposit(uint256 poolId, address indexed participant, uint256 amount);
    event ParticipantRemoved(uint256 poolId, address indexed participant);
    event JoinedPoolsRemoved(uint256 poolId, address indexed participant);
    event WinnerSet(uint256 poolId, address indexed winner, uint256 amount);
    event WinningsClaimed(uint256 poolId, address indexed winner, uint256 amount);
    event RemainingBalanceCollected(uint256 poolId, address indexed host, uint256 amount);
    event PoolStartTimeChanged(uint256 poolId, uint256 startTime);
    event PoolEndTimeChanged(uint256 poolId, uint256 endTime);
    event WinningForfeited(uint256 poolId, address indexed winner, uint256 amount);
    event PoolNameChanged(uint256 poolId, string poolName);
    event ParticipantRejoined(uint256 poolId, address indexed participant);
    event SponsorshipAdded(uint256 poolId, address indexed sponsor, uint256 amount);

    /// @dev Error when caller is not authorized.
    error Unauthorized(address caller);
    error EventStarted(uint256 timeNow, uint256 timeStart, address caller);

    enum POOLSTATUS {
        INACTIVE,
        DEPOSIT_ENABLED,
        STARTED,
        ENDED,
        DELETED
    }

    struct PoolAdmin {
        address host;
    }

    struct PoolDetail {
        uint40 timeStart;
        uint40 timeEnd;
        string poolName;
        uint256 depositAmountPerPerson;
    }

    struct PoolBalance {
        uint256 totalDeposits; // total deposit amount (won't reduce, for record)
        uint256 balance; // real current balance of pool
        uint256 sponsored; // extra balance from sponsor or participants
    }

    struct ParticipantDetail {
        uint256 deposit; // used for record
        uint120 participantIndex; // store index for easy removal
        uint120 joinedPoolsIndex; // store index for easy removal
        bool refunded;
    }

    struct WinnerDetail {
        uint256 amountWon;
        uint256 amountClaimed;
        uint40 timeWon;
        bool claimed;
        bool forfeited;
        bool alreadyInList; // check for skipping array.push operation
    }

    struct SponsorDetail {
        string name;
        uint256 amount;
    }

    // ----------------------------------------------------------------------------
    // Participant Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Deposit tokens into a pool
     * @param poolId The pool id
     * @param amount The amount to deposit
     * @dev Pool status must be DEPOSIT_ENABLED
     * @dev Pool must not have started
     * @dev User must not be a participant
     * @dev Amount must be equal to depositAmountPerPerson
     * @dev Emits Deposit event
     */
    function deposit(uint256 poolId, uint256 amount) external returns (bool);

    /**
     * @notice Claim winning from a pool
     * @param poolId The pool id
     * @dev Pool status must be ENDED
     * @dev User must be a winner
     * @dev User must not have claimed
     * @dev Emits WinningClaimed event
     */
    function claimWinning(uint256 poolId, address winner) external;

    /// @notice Claim winnings from multiple pools
    function claimWinnings(uint256[] calldata poolIds, address[] calldata _winners) external;

    // ----------------------------------------------------------------------------
    // Host Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Create a new pool, current impletation allows only whitelisted address to create pool
     * @param timeStart The start time of the pool
     * @param timeEnd The end time of the pool
     * @param poolName The name of the pool
     * @param depositAmountPerPerson The amount to deposit per person
     * @param token The token to use for the pool
     * @dev Pool status will be INACTIVE
     * @dev Emits PoolCreated event
     */
    function createPool(
        uint40 timeStart,
        uint40 timeEnd,
        string calldata poolName,
        uint256 depositAmountPerPerson, // Can be 0 in case of sponsored pool
        address token
    ) external returns (uint256);

    /**
     * @notice Enable deposit for a pool, to prevent frontrunning deposit
     * @param poolId The pool id
     * @dev Only the host can enable deposit
     * @dev Pool status must be INACTIVE
     * @dev Pool status will be changed to DEPOSIT_ENABLED
     * @dev Emits PoolStatusChanged event
     */
    function enableDeposit(uint256 poolId) external;

    /**
     * @notice Change start time of a pool
     * @param poolId The pool id
     * @param timeStart The new start time
     * @dev Only the host can change start time
     * @dev Pool status must not be STARTED
     */
    function changeStartTime(uint256 poolId, uint40 timeStart) external;

    /**
     * @notice Change end time of a pool
     * @param poolId The pool id
     * @param timeEnd The new end time
     * @dev Only the host can change end time
     * @dev Pool status must not be ENDED
     */
    function changeEndTime(uint256 poolId, uint40 timeEnd) external;

    /**
     * @notice Start a pool, to prevent further deposits
     * @param poolId The pool id
     * @dev Only the host can start the pool
     * @dev Pool status must be DEPOSIT_ENABLED
     * @dev Pool status will be changed to STARTED
     * @dev Emits PoolStatusChanged event
     */
    function startPool(uint256 poolId) external;

    /**
     * @notice Re-enable deposit for a pool in case host wants to accept more deposit
     * @param poolId The pool id
     * @dev Only the host can re-enable deposit
     * @dev Pool status must be STARTED
     * @dev Pool status will be changed to DEPOSIT_ENABLED
     * @dev Emits PoolStatusChanged event
     */
    function reenableDeposit(uint256 poolId) external;

    /**
     * @notice End a pool
     * @param poolId The pool id
     * @dev Only the host can end the pool
     * @dev Pool status must be STARTED
     * @dev Pool status will be changed to ENDED
     * @dev Emits PoolStatusChanged event
     */
    function endPool(uint256 poolId) external;

    /**
     * @notice Delete a pool
     * @param poolId The pool id
     * @dev Only the host can delete the pool
     * @dev Pool status will be changed to DELETED
     * @dev Emits PoolStatusChanged event
     */
    function deletePool(uint256 poolId) external;

    /**
     * @notice Set winner of pool
     * @param poolId The pool id
     * @param winner The winner address
     * @param amount The amount to set as winner
     * @dev Only the host can set the winner
     * @dev Winner must be a participant
     * @dev Amount must be greater than or equal to pool balance
     * @dev Emits WinnerSet event
     */
    function setWinner(uint256 poolId, address winner, uint256 amount) external;

    /// @notice Set multiple winners of pool
    function setWinners(uint256 poolId, address[] calldata _winners, uint256[] calldata amounts) external;

    /**
     * @notice Refund a participant
     * @param poolId The pool id
     * @param participant The participant address
     * @dev Only the host can refund a participant
     * @dev Pool status must be STARTED
     * @dev Participant must be a participant
     * @dev Pool balance must be greater than 0
     * @dev Emits Refund event
     */
    function refundParticipant(uint256 poolId, address participant, uint256 amount) external;

    /**
     * @notice Collect remaining balance if any
     * @param poolId The pool id
     * @dev Only send to host
     * @dev Emits RemainingBalanceCollected event
     */
    function collectRemainingBalance(uint256 poolId) external;

    /**
     * @notice Forfeit winnings of a winner back to pool,
     *          used when winner not claim for long time
     * @param poolId The pool id
     * @param winner The winner address
     * @dev Only the host can forfeit winnings
     * @dev Winner must have winnings
     * @dev Winner must not have claimed
     * @dev Emits WinningForfeited event
     */
    function forfeitWinnings(uint256 poolId, address winner) external;

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    // @dev Get everthing about a pool
    function getAllPoolInfo(uint256 poolId)
        external
        view
        returns (
            IPool.PoolAdmin memory _poolAdmin,
            IPool.PoolDetail memory _poolDetail,
            IPool.PoolBalance memory _poolBalance,
            IPool.POOLSTATUS _poolStatus,
            address _poolToken,
            address[] memory _participants,
            address[] memory _winners
        );

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    function pause() external;
    function unpause() external;
    // function paused() external view returns (bool);
    function emergencyWithdraw(IERC20 token, uint256 amount) external;
    // function pendingOwner() external view returns (address);
    // function transferOwnership(address newOwner) external;
    // function acceptOwnership() external;
    // function supportsInterface(bytes4 interfaceId) external view returns (bool);
    // function hasRole(bytes32 role, address account) external view returns (bool);
    // function getRoleAdmin(bytes32 role) external view returns (bytes32);
    // function grantRole(bytes32 role, address account) external;
    // function revokeRole(bytes32 role, address account) external;
    // function renounceRole(bytes32 role, address callerConfirmation) external;
}
