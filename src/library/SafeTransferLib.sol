// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "../interface/IERC20.sol";

interface IERC20Internal {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title SafeTransferLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to manage transfers of tokens, even if calls to the transfer or transferFrom functions are not
/// returning a boolean.
library SafeTransferLib {
    error NoCode();
    error TransferReverted();
    error TransferReturnedFalse();
    error TransferFromReverted();
    error TransferFromReturnedFalse();

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if(address(token).code.length == 0) {
            revert NoCode();
        }

        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IERC20Internal.transfer, (to, value)));
        if(!success) {
            revert TransferReverted();
        }
        if(returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert TransferReturnedFalse();
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if(address(token).code.length == 0) {
            revert NoCode();
        }

        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeCall(IERC20Internal.transferFrom, (from, to, value)));
        if(!success) {
            revert TransferFromReverted();
        }
        if(returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert TransferFromReturnedFalse();
        }
    }
}
