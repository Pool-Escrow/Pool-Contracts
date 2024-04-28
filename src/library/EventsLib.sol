// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library EventsLib {
    event PoolCreated(uint256 poolId, address host, string poolName);
    event PoolStatusChanged(uint256 poolId, IPool.POOLSTATUS status);
    event Refund(uint256 poolId, address participant, uint256 amount);
    event Deposit(uint256 poolId, address participant, uint256 amount);
    event FeesCollected(uint256 poolId, address host, uint256 fees);
    event FeesCharged(uint256 poolId, address participant, uint256 fees, bool chargedAll);
    event CohostAdded(uint256 poolId, address cohost);
    event CohostRemoved(uint256 poolId, address cohost);
    event ParticipantRemoved(uint256 poolId, address participant);
    event JoinedPoolsRemoved(uint256 poolId, address participant);
    event WinnerSet(uint256 poolId, address winner, uint256 amount);
    event WinningClaimed(uint256 poolId, address winner, uint256 amount);
    event RemainingBalanceCollected(uint256 poolId, address host, uint256 amount);
}
