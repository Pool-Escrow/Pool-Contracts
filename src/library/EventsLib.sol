// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library EventsLib {
    event PoolCreated(
        uint256 poolId,
        address indexed host,
        string poolName,
        uint256 depositAmountPerPerson,
        address indexed token
    );
    event Deposit(uint256 poolId, address indexed participant, uint256 amount);
    event ExtraDeposit(uint256 poolId, address indexed participant, uint256 amount);
    event WinnerSet(uint256 poolId, address indexed winner, uint256 amount);
    event WinningsClaimed(uint256 poolId, address indexed winner, uint256 amount);
    event RemainingBalanceCollected(uint256 poolId, address indexed host, uint256 amount);
    event SponsorshipAdded(uint256 poolId, address indexed sponsor, uint256 amount, string oneTimeShortMessage);
}
