// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Minimal mock EntryPoint for testing ERC-4337 account validation.
contract MockEntryPoint {
    // Allows test to call validateUserOp on the account as the EntryPoint
    function validateUserOp(
        address account,
        bytes calldata callData
    ) external returns (uint256) {
        (bool success, bytes memory ret) = account.call(callData);
        require(success, "validateUserOp failed");
        return abi.decode(ret, (uint256));
    }
}
