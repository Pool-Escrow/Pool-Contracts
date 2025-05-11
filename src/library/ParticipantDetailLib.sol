// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPool} from "../interface/IPool.sol";

library ParticipantDetailLib {
    function getDeposit(IPool.ParticipantDetail storage self) internal view returns (uint256) {
        return self.deposit;
    }

    function setParticipantIndex(IPool.ParticipantDetail storage self, uint256 _participantIndex) internal {
        self.participantIndex = uint120(_participantIndex);
    }

    function getParticipantIndex(IPool.ParticipantDetail storage self) internal view returns (uint256) {
        return self.participantIndex;
    }
}
