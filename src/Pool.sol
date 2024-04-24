// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// Interfaces
import {IPool} from "./interface/IPool.sol";
/// Libraries
import "./library/ConstantsLib.sol";
import {EventsLib} from "./library/EventsLib.sol";
import {ErrorsLib} from "./library/ErrorsLib.sol";
import {PoolAdminLib} from "./library/PoolAdminLib.sol";
import {PoolDetailLib} from "./library/PoolDetailLib.sol";
import {PoolBalanceLib} from "./library/PoolBalanceLib.sol";
import {ParticipantDetailLib} from "./library/ParticipantDetailLib.sol";

/// Dependencies
import {Owned} from "solmate/auth/Owned.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Pool is IPool, Owned, Pausable {
    using PoolAdminLib for IPool.PoolAdmin;
    using PoolDetailLib for IPool.PoolDetail;
    using PoolBalanceLib for IPool.PoolBalance;
    using ParticipantDetailLib for IPool.ParticipantDetail;

    uint256 public latestPoolId; // Start from 1, 0 is invalid

    /// @dev Pool specific mappings
    mapping(uint256 => PoolAdmin) public poolAdmin;
    mapping(uint256 => PoolDetail) public poolDetail;
    mapping(uint256 => IERC20) public poolToken;
    mapping(uint256 => PoolBalance) public poolBalance;
    mapping(uint256 => POOLSTATUS) public poolStatus;
    mapping(uint256 => address[]) public participants;

    /// @dev Pool admin specific mappings
    mapping(address => uint256[]) public createdPools;
    mapping(address => mapping(uint256 => bool)) public isHost;
    mapping(address => mapping(uint256 => bool)) public isCohost;
    mapping(address => mapping(uint256 => uint256)) public cohostIndex; // Store index for easy removal

    /// @dev User specific mappings
    mapping(address => uint256[]) public joinedPools;
    mapping(address => mapping(uint256 => bool)) public isParticipant;
    mapping(address => mapping(uint256 => ParticipantDetail)) public participantDetail;

    /// @notice Modifier to check if user is host or cohost
    modifier onlyHostOrCohost(uint256 poolId) {
        if (!isHost[msg.sender][poolId]) {
            if (!isCohost[msg.sender][poolId]) {
                revert ErrorsLib.Unauthorized(msg.sender);
            }
        }
        _;
    }

    /// @notice Modifier to check if user is host
    modifier onlyHost(uint256 poolId) {
        if (!isHost[msg.sender][poolId]) {
            revert ErrorsLib.Unauthorized(msg.sender);
        }
        _;
    }

    constructor() Owned(msg.sender) {}

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
    function deposit(uint256 poolId, uint256 amount) external whenNotPaused returns (bool) {
        require(poolStatus[poolId] == POOLSTATUS.DEPOSIT_ENABLED, "Deposit not enabled");
        require(block.timestamp <= poolDetail[poolId].getTimeStart(), "Pool started");
        require(isParticipant[msg.sender][poolId] == false, "Already in pool");
        require(amount == poolDetail[poolId].getDepositAmountPerPerson(), "Deposit amount not correct");

        // Transfer tokens from user to pool
        bool success = poolToken[poolId].transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        // Update pool details
        poolBalance[poolId].totalDeposits += amount;
        poolBalance[poolId].balance += amount;
        participantDetail[msg.sender][poolId].setParticipantIndex(participants[poolId].length);
        participants[poolId].push(msg.sender);

        // Update participant details
        participantDetail[msg.sender][poolId].setJoinedPoolsIndex(joinedPools[msg.sender].length);
        joinedPools[msg.sender].push(poolId);
        isParticipant[msg.sender][poolId] = true;
        participantDetail[msg.sender][poolId].deposit = amount;

        emit EventsLib.Deposit(poolId, msg.sender, amount);
        return true;
    }

    /**
     * @notice Withdraw fees collected
     * @param poolId The pool id
     * @dev Only the host or cohost can withdraw fees
     * @dev Pool status must be ENDED
     * @dev Pool fees collected must be greater than 0
     * @dev Emits FeesCollected event
     */
    function selfRefund(uint256 poolId) external whenNotPaused {
        require(poolStatus[poolId] != POOLSTATUS.ENDED, "Pool already ended");
        require(isParticipant[msg.sender][poolId], "Not a participant");
        require(participantDetail[msg.sender][poolId].isRefunded() == false, "Already refunded");

        // Apply fees if pool is not deleted
        if (poolStatus[poolId] != POOLSTATUS.DELETED) {
            _applyFees(poolId);
        }
        _refund(poolId, msg.sender);
    }

    // ----------------------------------------------------------------------------
    // Host Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Create a new pool
     * @param timeStart The start time of the pool
     * @param timeEnd The end time of the pool
     * @param poolName The name of the pool
     * @param depositAmountPerPerson The amount to deposit per person
     * @param penaltyFeeRate The penalty fee rate
     * @param token The token to use for the pool
     * @param cohosts The cohosts of the pool
     * @dev Pool status will be INACTIVE
     * @dev Emits PoolCreated event
     */
    function createPool(
        uint40 timeStart,
        uint40 timeEnd,
        string calldata poolName,
        uint256 depositAmountPerPerson,
        uint16 penaltyFeeRate,
        IERC20 token,
        address[] calldata cohosts
    ) external whenNotPaused returns (uint256) {
        require(timeStart < timeEnd, "Invalid timing");
        require(address(token) != address(0), "Invalid token");
        require(penaltyFeeRate <= FEES_PRECISION, "Invalid fees rate");

        // Increment pool id
        latestPoolId++;

        // Pool details
        poolDetail[latestPoolId].setTimeStart(timeStart);
        poolDetail[latestPoolId].setTimeEnd(timeEnd);
        poolDetail[latestPoolId].setPoolName(poolName);
        poolDetail[latestPoolId].setDepositAmountPerPerson(depositAmountPerPerson);

        // Pool admin details
        poolAdmin[latestPoolId].setPenaltyFeeRate(penaltyFeeRate);
        poolAdmin[latestPoolId].setHost(msg.sender);
        isHost[msg.sender][latestPoolId] = true;
        createdPools[msg.sender].push(latestPoolId);

        // Pool token
        poolToken[latestPoolId] = token;

        // Add cohosts
        if (cohosts.length != 0) {
            for (uint256 i = 0; i < cohosts.length; i++) {
                require(cohosts[i] != msg.sender, "Host cannot be cohost");
                PoolAdminLib.addCohost(poolAdmin, cohostIndex, isCohost, cohosts[i], latestPoolId);
            }
        }
        emit EventsLib.PoolCreated(latestPoolId, msg.sender, poolName);
        return latestPoolId;
    }

    /**
     * @notice Enable deposit for a pool
     * @param poolId The pool id
     * @dev Only the host or cohost can enable deposit
     * @dev Pool status must be INACTIVE
     * @dev Pool status will be changed to DEPOSIT_ENABLED
     * @dev Emits PoolStatusChanged event
     */
    function enableDeposit(uint256 poolId) external onlyHostOrCohost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.INACTIVE, "Pool already active");

        poolStatus[poolId] = POOLSTATUS.DEPOSIT_ENABLED;
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.DEPOSIT_ENABLED);
    }

    /**
     * @notice Start a pool
     * @param poolId The pool id
     * @dev Only the host or cohost can start the pool
     * @dev Pool status must be DEPOSIT_ENABLED
     * @dev Pool status will be changed to STARTED
     * @dev Emits PoolStatusChanged event
     */
    function startPool(uint256 poolId) external onlyHostOrCohost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.DEPOSIT_ENABLED, "Deposit not enabled yet");

        poolStatus[poolId] = POOLSTATUS.STARTED;
        poolDetail[poolId].setTimeStart(uint40(block.timestamp)); // update actual start time
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.STARTED);
    }

    /**
     * @notice End a pool
     * @param poolId The pool id
     * @dev Only the host or cohost can end the pool
     * @dev Pool status must be STARTED
     * @dev Pool status will be changed to ENDED
     * @dev Emits PoolStatusChanged event
     */
    function endPool(uint256 poolId) external onlyHostOrCohost(poolId) whenNotPaused {
        require(poolStatus[poolId] == POOLSTATUS.STARTED, "Pool not started");

        poolStatus[poolId] = POOLSTATUS.ENDED;
        poolDetail[poolId].setTimeEnd(uint40(block.timestamp)); // update actual end time
        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.ENDED);
    }

    /**
     * @notice Refund a participant
     * @param poolId The pool id
     * @param participant The participant address
     * @dev Only the host or cohost can refund a participant
     * @dev Pool status must be STARTED
     * @dev Participant must be a participant
     * @dev Participant must not be refunded
     * @dev Pool balance must be greater than 0
     * @dev Emits Refund event
     */
    function refundParticipant(uint256 poolId, address participant) external onlyHostOrCohost(poolId) whenNotPaused {
        require(isParticipant[participant][poolId], "Not a participant");
        require(participantDetail[participant][poolId].isRefunded() == false, "Already refunded");
        require(poolBalance[poolId].getBalance() > 0, "No balance");

        _refund(poolId, participant);
    }

    /**
     * @notice Delete a pool
     * @param poolId The pool id
     * @dev Only the host can delete the pool
     * @dev Pool status will be changed to DELETED
     * @dev Emits PoolStatusChanged event
     */
    function deletePool(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        poolStatus[poolId] = POOLSTATUS.DELETED;

        emit EventsLib.PoolStatusChanged(poolId, POOLSTATUS.DELETED);
    }

    /**
     * @notice Collect fees
     * @param poolId The pool id
     * @dev Only send to host
     * @dev Emits FeesCollected event
     */
    function collectFees(uint256 poolId) external whenNotPaused {
        // Transfer fees to host
        uint256 fees = poolBalance[poolId].getFeesAccumulated() - poolBalance[poolId].getFeesCollected();
        poolBalance[poolId].balance -= fees;
        poolBalance[poolId].feesCollected += fees;

        bool success = poolToken[poolId].transfer(poolAdmin[poolId].getHost(), fees);
        require(success, "Transfer failed");

        emit EventsLib.FeesCollected(poolId, poolAdmin[poolId].getHost(), fees);
    }

    /**
     * @notice Add a cohost
     * @param poolId The pool id
     * @param cohost The cohost address
     * @dev Only the host can add a cohost
     * @dev Co-host must not be the host
     * @dev Co-host must not be a cohost
     * @dev Emits CohostAdded event
     */
    function addCohost(uint256 poolId, address cohost) external onlyHost(poolId) whenNotPaused {
        require(!isCohost[cohost][poolId], "Cohost already exist");
        require(cohost != poolAdmin[poolId].getHost(), "Host cannot be cohost");

        PoolAdminLib.addCohost(poolAdmin, cohostIndex, isCohost, cohost, poolId);

        emit EventsLib.CohostAdded(poolId, cohost);
    }

    /**
     * @notice Remove a cohost
     * @param poolId The pool id
     * @param cohost The cohost address
     * @dev Only the host can remove a cohost
     * @dev Co-host must exist
     * @dev Emits CohostRemoved event
     */
    function removeCohost(uint256 poolId, address cohost) external onlyHost(poolId) whenNotPaused {
        require(isCohost[cohost][poolId], "Cohost does not exist");

        PoolAdminLib.removeCohost(poolAdmin, cohostIndex, isCohost, cohost, poolId);
        emit EventsLib.CohostRemoved(poolId, cohost);
    }

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    function getHost(uint256 poolId) external view returns (address) {
        return poolAdmin[poolId].getHost();
    }

    function getPoolsCreatedBy(address host) external view returns (uint256[] memory) {
        return createdPools[host];
    }

    function getPoolsJoinedBy(address participant) external view returns (uint256[] memory) {
        return joinedPools[participant];
    }

    function getParticipants(uint256 poolId) external view returns (address[] memory) {
        return participants[poolId];
    }

    function getParticipantDeposit(address participant, uint256 poolId) public view returns (uint256) {
        return ParticipantDetailLib.getDeposit(participantDetail, participant, poolId);
    }

    function getPoolFeeRate(uint256 poolId) public view returns (uint16) {
        return poolAdmin[poolId].getPenaltyFeeRate();
    }

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(IERC20 token, uint256 amount) external onlyOwner whenPaused {
        bool success = token.transfer(msg.sender, amount);
        require(success, "Transfer failed");
    }

    // ----------------------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------------------

    /**
     * @notice Refund all participants
     * @param poolId The pool id
     * @dev Only the host or cohost can refund all participants
     * @dev Pool status must be STARTED
     * @dev Pool balance must be greater than 0
     * @dev Emits Refund event
     */
    function _refund(uint256 poolId, address participant) internal {
        uint256 amount = ParticipantDetailLib.getDeposit(participantDetail, participant, poolId)
            - ParticipantDetailLib.getFeesCharged(participantDetail, participant, poolId);

        // Update participant details
        participantDetail[participant][poolId].refunded = true;
        participantDetail[participant][poolId].deposit = 0;

        // Update pool balance
        poolBalance[poolId].balance -= amount;
        poolBalance[poolId].totalDeposits -= amount;

        // Delete participant from pool
        ParticipantDetailLib.removeParticipantFromPool(
            participantDetail, participants, isParticipant, participant, poolId
        );

        // Delete pool from participant
        ParticipantDetailLib.removeFromJoinedPool(participantDetail, joinedPools, participant, poolId);

        bool success = poolToken[poolId].transfer(participant, amount);
        require(success, "Transfer failed");

        emit EventsLib.Refund(poolId, participant, amount);
    }

    /**
     * @notice Apply fees to a participant
     * @param poolId The pool id
     */
    function _applyFees(uint256 poolId) internal {
        // Charge fees if event is < 24 hours to start or started
		uint40 timeStart = poolDetail[poolId].getTimeStart();
        if (
            block.timestamp >= timeStart - 1 days
                && block.timestamp <= timeStart
        ) {
            uint256 fees = (getPoolFeeRate(poolId) * getParticipantDeposit(msg.sender, poolId)) / FEES_PRECISION;
            participantDetail[msg.sender][poolId].feesCharged += fees;
            poolBalance[poolId].feesAccumulated += fees;

            emit EventsLib.FeesCharged(poolId, msg.sender, fees, false);
        } else if (block.timestamp > timeStart) {
            uint256 fees = getParticipantDeposit(msg.sender, poolId);
            participantDetail[msg.sender][poolId].feesCharged += fees;
            poolBalance[poolId].feesAccumulated += fees;

            emit EventsLib.FeesCharged(poolId, msg.sender, fees, true);
        }
    }
}
