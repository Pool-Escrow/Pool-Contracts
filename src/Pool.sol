// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// Interfaces
import {IPool} from "./interface/IPool.sol";
import {IERC20} from "./interface/IERC20.sol";

/// Libraries
import {UtilsLib} from "./library/UtilsLib.sol";
import {PoolDetailLib} from "./library/PoolDetailLib.sol";
import {ParticipantDetailLib} from "./library/ParticipantDetailLib.sol";
import {PoolBalanceLib} from "./library/PoolBalanceLib.sol";
import {WinnerDetailLib} from "./library/WinnerDetailLib.sol";
import {SafeTransferLib} from "./library/SafeTransferLib.sol";
import {ErrorsLib} from "./library/ErrorsLib.sol";
import {EventsLib} from "./library/EventsLib.sol";

/// Dependencies
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuardTransient as ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract Pool is IPool, AccessControl, Pausable, ReentrancyGuard {
    using PoolDetailLib for PoolDetail;
    using ParticipantDetailLib for ParticipantDetail;
    using PoolBalanceLib for PoolBalance;
    using WinnerDetailLib for WinnerDetail;
    using SafeTransferLib for IERC20;

    uint256 public latestPoolId; // Start from 1, 0 is invalid
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint40 public constant TIME_DELAY = 7 days;

    /// @dev Pool specific mappings
    mapping(uint256 => PoolDetail) public poolDetail;
    mapping(uint256 => IERC20) public poolToken;
    mapping(uint256 => PoolBalance) public poolBalance;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => address[]) public winners;

    /// @dev Pool admin specific mappings
    mapping(address => uint256[]) public createdPools;
    mapping(address => mapping(uint256 poolId => bool)) public isHost;

    /// @dev User specific mappings
    mapping(address => uint256[]) public joinedPools;
    mapping(address => mapping(uint256 poolId => bool)) public isParticipant;
    mapping(address => mapping(uint256 poolId => ParticipantDetail)) public participantDetail;
    mapping(address => mapping(uint256 poolId => WinnerDetail)) public winnerDetail;
    mapping(address => uint256[]) public claimablePools;

    /// @dev Sponsor specific mappings
    mapping(address => mapping(uint256 poolId => uint256)) public sponsorAmount;
    mapping(uint256 => address[]) public sponsors;
    mapping(uint256 => string[]) public sponsorMessages;

    /// @notice Modifier to check if user is host
    modifier onlyHost(uint256 poolId) {
        if (!isHost[msg.sender][poolId]) {
            revert ErrorsLib.Unauthorized(msg.sender);
        }
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // ----------------------------------------------------------------------------
    // Participant Functions
    // ----------------------------------------------------------------------------

    function deposit(uint256 poolId, uint256 amount) external whenNotPaused nonReentrant returns (bool) {
        require(poolDetail[poolId].getTimeStart() < block.timestamp, "Pool not started");
        require(poolDetail[poolId].getTimeEnd() >= block.timestamp, "Pool ended");
        require(!isParticipant[msg.sender][poolId], "Already in pool");
        uint256 amountPerPerson = poolDetail[poolId].getDepositAmountPerPerson();
        require(amount >= amountPerPerson, "Insufficient amount");

        // Excess as extra donation
        if (amount > amountPerPerson) {
            poolBalance[poolId].sponsored += amount - amountPerPerson;
            emit EventsLib.ExtraDeposit(poolId, msg.sender, amount - amountPerPerson);
        }

        // Update pool details
        poolBalance[poolId].totalDeposits += amount;
        poolBalance[poolId].balance += amount;
        participantDetail[msg.sender][poolId].setParticipantIndex(participants[poolId].length);
        participants[poolId].push(msg.sender);

        // Update participant details
        joinedPools[msg.sender].push(poolId);
        isParticipant[msg.sender][poolId] = true;
        participantDetail[msg.sender][poolId].deposit = amountPerPerson;

        // Transfer tokens from user to pool
        poolToken[poolId].safeTransferFrom(msg.sender, address(this), amount);

        emit EventsLib.Deposit(poolId, msg.sender, amount);
        return true;
    }

    function claimWinnings(uint256[] calldata poolIds, address[] calldata _winners) external whenNotPaused {
        require(poolIds.length == poolIds.length, "Invalid input");
        for (uint256 i; i < poolIds.length; i++) {
            claimWinning(poolIds[i], _winners[i]);
        }
    }

    function claimWinning(uint256 poolId, address winner) public whenNotPaused {
        uint256 amount = winnerDetail[winner][poolId].getAmountWon() - winnerDetail[winner][poolId].getAmountClaimed();
        require(amount > 0, "No winnings");

        winnerDetail[winner][poolId].addAmountClaimed(amount);
        poolToken[poolId].safeTransfer(winner, amount);

        emit EventsLib.WinningsClaimed(poolId, winner, amount);
    }

    // ----------------------------------------------------------------------------
    // Sponsor Functions
    // ----------------------------------------------------------------------------

    function sponsor(uint256 poolId, uint256 amount, string calldata oneTimeShortMessage) external whenNotPaused nonReentrant {
        require(poolDetail[poolId].getPoolAdmin() != address(0), "Pool not created");
        require(poolDetail[poolId].getTimeEnd() >= block.timestamp, "Pool ended");
        require(amount > 0, "Invalid amount");

        // Update pool details
        poolBalance[poolId].totalDeposits += amount;
        poolBalance[poolId].balance += amount;
        poolBalance[poolId].sponsored += amount;

        // Update sponsor details
        if (sponsorAmount[msg.sender][poolId] == 0) {
            sponsorMessages[poolId].push(oneTimeShortMessage);
            sponsors[poolId].push(msg.sender);
        }
        sponsorAmount[msg.sender][poolId] += amount;

        // Transfer tokens from user to pool
        poolToken[poolId].safeTransferFrom(msg.sender, address(this), amount);

        emit EventsLib.SponsorshipAdded(poolId, msg.sender, amount, oneTimeShortMessage);
    }

    // ----------------------------------------------------------------------------
    // Host Functions
    // ----------------------------------------------------------------------------

    function createPool(
        uint40 timeStart,
        uint40 timeEnd,
        string calldata poolName,
        uint256 depositAmountPerPerson, // Can be 0 in case of sponsored pool
        address token,
        uint16 totalWinners, // Optional
        uint256 amountPerWinner // Optional
    ) external whenNotPaused returns (uint256) {
        require(timeStart < timeEnd, "Invalid timing");
        require(UtilsLib.isContract(token), "Token not contract");

        // Increment pool id
        latestPoolId++;

        // Pool admin details
        poolDetail[latestPoolId].setPoolAdmin(msg.sender);
        isHost[msg.sender][latestPoolId] = true;
        createdPools[msg.sender].push(latestPoolId);

        // Pool details
        poolDetail[latestPoolId].setTimeStart(timeStart);
        poolDetail[latestPoolId].setTimeEnd(timeEnd);
        poolDetail[latestPoolId].setPoolName(poolName);
        poolDetail[latestPoolId].setDepositAmountPerPerson(depositAmountPerPerson);
        if (totalWinners > 0) {
            poolDetail[latestPoolId].setTotalWinners(totalWinners);
        }
        if (amountPerWinner > 0) {
            poolDetail[latestPoolId].setAmountPerWinner(amountPerWinner);
        }

        // Pool token
        poolToken[latestPoolId] = IERC20(token);

        emit EventsLib.PoolCreated(latestPoolId, msg.sender, poolName, depositAmountPerPerson, token);
        return latestPoolId;
    }

    function setWinnersEvenly(uint256 poolId, address[] calldata _winners) external onlyHost(poolId) whenNotPaused {
        uint16 totalWinners = poolDetail[poolId].getTotalWinners();
        uint256 amountPerWinner = poolDetail[poolId].getAmountPerWinner();
        require(totalWinners > 0, "Total winners not set");
        require(_winners.length == totalWinners, "Invalid number of winners");

        if (amountPerWinner == 0) {
            amountPerWinner = poolBalance[poolId].getBalance() / totalWinners;
        }

        for (uint256 i; i < totalWinners; i++) {
            setWinner(poolId, _winners[i], amountPerWinner);
        }
    }

    function setWinners(uint256 poolId, address[] calldata _winners, uint256[] calldata amounts)
        external
        onlyHost(poolId)
        whenNotPaused
    {
        require(_winners.length == amounts.length, "Invalid input");

        for (uint256 i; i < _winners.length; i++) {
            setWinner(poolId, _winners[i], amounts[i]);
        }
    }

    function setWinner(uint256 poolId, address winner, uint256 amount) public onlyHost(poolId) whenNotPaused {
        require(poolDetail[poolId].getTimeEnd() < block.timestamp, "Pool not ended");
        require(isParticipant[winner][poolId], "Not a participant");
        require(amount <= poolBalance[poolId].getBalance(), "Not enough balance");
        require(winnerDetail[winner][poolId].getAmountClaimed() == 0, "Already claimed");

        // Update pool balance
        poolBalance[poolId].balance -= amount;

        // Update winner details
        winnerDetail[winner][poolId].addAmountWon(amount);

        // Push into array if not already in
        if (winnerDetail[winner][poolId].getAmountWon() == 0) {
            winners[poolId].push(winner);
            claimablePools[winner].push(poolId);
        }
        emit EventsLib.WinnerSet(poolId, winner, amount);
    }

    function collectRemainingBalance(uint256 poolId) external onlyHost(poolId) whenNotPaused {
        require(poolDetail[poolId].getTimeEnd() + TIME_DELAY < block.timestamp, "Pool not ended");
        uint256 amount = poolBalance[poolId].getBalance();
        require(amount > 0, "Nothing to withdraw");

        poolBalance[poolId].balance = 0;
        address host = poolDetail[poolId].getPoolAdmin();
        poolToken[poolId].safeTransfer(host, amount);

        emit EventsLib.RemainingBalanceCollected(poolId, host, amount);
    }

    // ----------------------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------------------

    function getHost(uint256 poolId) external view returns (address) {
        return poolDetail[poolId].getPoolAdmin();
    }

    function getPoolName(uint256 poolId) external view returns (string memory) {
        return poolDetail[poolId].getPoolName();
    }

    function getPoolStartTime(uint256 poolId) external view returns (uint40) {
        return poolDetail[poolId].getTimeStart();
    }

    function getPoolEndTime(uint256 poolId) external view returns (uint40) {
        return poolDetail[poolId].getTimeEnd();
    }

    function getSponsors(uint256 poolId) external view returns (address[] memory) {
        return sponsors[poolId];
    }

    function getSponsorMessages(uint256 poolId) external view returns (string[] memory) {
        return sponsorMessages[poolId];
    }

    function getPoolDetail(uint256 poolId) external view returns (IPool.PoolDetail memory) {
        return poolDetail[poolId];
    }

    function getPoolDeposits(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getDepositAmount();
    }

    function getPoolBalance(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getBalance();
    }

    function getPoolToken(uint256 poolId) external view returns (address) {
        return address(poolToken[poolId]);
    }

    function getSponsorshipAmount(uint256 poolId) external view returns (uint256) {
        return poolBalance[poolId].getSponsorshipAmount();
    }

    function getParticipantDeposit(address participant, uint256 poolId) public view returns (uint256) {
        return participantDetail[participant][poolId].getDeposit();
    }

    function getParticipantIndex(address participant, uint256 poolId) external view returns (uint256) {
        return participantDetail[participant][poolId].getParticipantIndex();
    }

    function getParticipantDetail(address participant, uint256 poolId)
        public
        view
        returns (IPool.ParticipantDetail memory)
    {
        return participantDetail[participant][poolId];
    }

    function getWinningAmount(uint256 poolId, address winner) external view returns (uint256) {
        return winnerDetail[winner][poolId].getAmountWon();
    }

    function getWinnerTimeWon(uint256 poolId, address winner) external view returns (uint40) {
        return winnerDetail[winner][poolId].getTimeWon();
    }

    function getWinnerAmountClaimed(uint256 poolId, address winner) external view returns (uint256) {
        return winnerDetail[winner][poolId].getAmountClaimed();
    }

    function getWinnerDetail(uint256 poolId, address winner) external view returns (IPool.WinnerDetail memory) {
        return winnerDetail[winner][poolId];
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

    function getWinners(uint256 poolId) external view returns (address[] memory) {
        return winners[poolId];
    }

    function getClaimablePools(address winner) external view returns (uint256[] memory, bool[] memory) {
        bool[] memory isClaimed = new bool[](claimablePools[winner].length);
        for (uint256 i; i < claimablePools[winner].length; i++) {
            isClaimed[i] = winnerDetail[winner][claimablePools[winner][i]].getAmountClaimed() > 0;
        }
        return (claimablePools[winner], isClaimed);
    }

    function getWinnersDetails(uint256 poolId) external view returns (address[] memory, IPool.WinnerDetail[] memory) {
        IPool.WinnerDetail[] memory _winners = new IPool.WinnerDetail[](winners[poolId].length);
        for (uint256 i; i < winners[poolId].length; i++) {
            _winners[i] = winnerDetail[winners[poolId][i]][poolId];
        }
        return (winners[poolId], _winners);
    }

    function getAllPoolInfo(uint256 poolId)
        external
        view
        returns (
            IPool.PoolDetail memory _poolDetail,
            IPool.PoolBalance memory _poolBalance,
            address _poolToken,
            address[] memory _participants,
            address[] memory _winners
        )
    {
        return (
            poolDetail[poolId],
            poolBalance[poolId],
            address(poolToken[poolId]),
            participants[poolId],
            winners[poolId]
        );
    }

    // ----------------------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------------------

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function emergencyWithdraw(IERC20 token, uint256 amount) external onlyRole(ADMIN_ROLE) whenPaused {
        token.safeTransfer(msg.sender, amount);
    }
}
