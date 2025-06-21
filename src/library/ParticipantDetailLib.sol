// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library ParticipantDetailLib {
    function removeParticipantFromPool(
        mapping(address => mapping(uint256 => IPool.ParticipantDetail)) storage participantDetail,
        mapping(uint256 => address[]) storage participants,
        mapping(address => mapping(uint256 => bool)) storage isParticipant,
        address participant,
        uint256 poolId
    ) internal {
        uint256 i = participantDetail[participant][poolId].participantIndex;
        assert(participant == participants[poolId][i]);
        if (i < participants[poolId].length - 1) {
            // Move last to replace current index
            address lastParticipant = participants[poolId][participants[poolId].length - 1];
            participants[poolId][i] = lastParticipant;
            participantDetail[lastParticipant][poolId].participantIndex = uint120(i);
        }
        participants[poolId].pop();
        isParticipant[participant][poolId] = false;

        emit IPool.ParticipantRemoved(poolId, participant);
    }

    function removeFromJoinedPool(
        mapping(address => mapping(uint256 => IPool.ParticipantDetail)) storage participantDetail,
        mapping(address => uint256[]) storage joinedPools,
        address participant,
        uint256 poolId
    ) internal {
        uint256 i = participantDetail[participant][poolId].joinedPoolsIndex;
        assert(poolId == joinedPools[participant][i]);
        if (i < joinedPools[participant].length - 1) {
            // Move last to replace current index
            uint256 lastPool = joinedPools[participant][joinedPools[participant].length - 1];
            joinedPools[participant][i] = lastPool;
            participantDetail[participant][lastPool].joinedPoolsIndex = uint120(i);
        }
        joinedPools[participant].pop();

        emit IPool.JoinedPoolsRemoved(poolId, participant);
    }
}
