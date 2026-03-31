// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRNSNameModuleV1} from "./IRNSNameModuleV1.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";

interface IERC7579Account {
    function executeFromExecutor(bytes32 mode, bytes calldata executionData) external returns (bytes[] memory);
}

interface IResolver {
    function setAddr(bytes32 node, address addr) external;
    function setName(bytes32 node, string calldata name) external;
    function setText(bytes32 node, string calldata key, string calldata value) external;
}

/// @title RNSNameModuleV1
/// @notice ERC-7579 executor module that lets smart accounts manage their own RNS records.
/// @dev Install as module type 2 (executor) on a khaaliAccount. On installation, supply
///      the RNS node (namehash) owned by the account encoded as `abi.encode(bytes32)`.
///      Each update function re-enters the account via `executeFromExecutor` so the
///      resolver sees `msg.sender == account`, satisfying the resolver's ownership check.
contract RNSNameModuleV1 is IRNSNameModuleV1 {

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @dev Maps each installed account address to its RNS node.
    mapping(address => bytes32) private _nodes;

    // -------------------------------------------------------------------------
    // ERC-7579 Module Lifecycle
    // -------------------------------------------------------------------------

    /// @inheritdoc IRNSNameModuleV1
    function onInstall(bytes calldata data) external {
        bytes32 node = abi.decode(data, (bytes32));
        _nodes[msg.sender] = node;
        emit NodeSet(msg.sender, node);
    }

    /// @inheritdoc IRNSNameModuleV1
    function onUninstall(bytes calldata) external {
        delete _nodes[msg.sender];
        emit NodeCleared(msg.sender);
    }

    /// @inheritdoc IRNSNameModuleV1
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == 2;
    }

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------

    /// @inheritdoc IRNSNameModuleV1
    function nodeOf(address account) external view returns (bytes32) {
        return _nodes[account];
    }

    // -------------------------------------------------------------------------
    // Resolver Update Actions
    // -------------------------------------------------------------------------

    /// @inheritdoc IRNSNameModuleV1
    function updateAddress(address resolver, address newAddr) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "RNSNameModuleV1: not installed");
        _executeViaAccount(msg.sender, resolver, abi.encodeCall(IResolver.setAddr, (node, newAddr)));
    }

    /// @inheritdoc IRNSNameModuleV1
    function updateTextRecord(address resolver, string calldata key, string calldata value) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "RNSNameModuleV1: not installed");
        _executeViaAccount(msg.sender, resolver, abi.encodeCall(IResolver.setText, (node, key, value)));
    }

    /// @inheritdoc IRNSNameModuleV1
    function updateName(address resolver, string calldata newName) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "RNSNameModuleV1: not installed");
        _executeViaAccount(msg.sender, resolver, abi.encodeCall(IResolver.setName, (node, newName)));
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /// @dev Calls `account.executeFromExecutor` with a single-call mode targeting `target`.
    ///      The account forwards the call to `target` with `callData`, appearing as
    ///      `msg.sender == account` to the target contract.
    function _executeViaAccount(address account, address target, bytes memory callData) internal {
        bytes memory execData = abi.encodePacked(target, uint256(0), callData);
        bytes32 mode = LibERC7579.encodeMode(
            LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
        );
        IERC7579Account(account).executeFromExecutor(mode, execData);
    }
}
