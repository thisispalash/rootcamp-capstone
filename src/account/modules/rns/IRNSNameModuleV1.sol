// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IRNSNameModuleV1
/// @notice Interface for the ERC-7579 executor module that lets smart accounts manage
///         their own RNS (Rootstock Name Service) records.
/// @dev Installed as a type-2 (executor) module on a khaaliAccount. Once installed
///      the module stores the ENS/RNS node that belongs to the account and exposes
///      helper methods that trigger resolver updates through `executeFromExecutor`.
interface IRNSNameModuleV1 {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a node is associated with an account during installation.
    /// @param account The smart account that installed the module.
    /// @param node   The RNS node (namehash) assigned to the account.
    event NodeSet(address indexed account, bytes32 indexed node);

    /// @notice Emitted when the node association is removed during uninstallation.
    /// @param account The smart account that uninstalled the module.
    event NodeCleared(address indexed account);

    // -------------------------------------------------------------------------
    // ERC-7579 Module Lifecycle
    // -------------------------------------------------------------------------

    /// @notice Called by the account during module installation.
    /// @dev    `data` must be ABI-encoded as `abi.encode(bytes32 node)`.
    ///         Stores the node and emits {NodeSet}.
    /// @param data ABI-encoded bytes32 RNS node to associate with msg.sender.
    function onInstall(bytes calldata data) external;

    /// @notice Called by the account during module uninstallation.
    /// @dev    Deletes the stored node for msg.sender and emits {NodeCleared}.
    ///         `data` is ignored.
    /// @param data Unused de-init data (kept for interface compliance).
    function onUninstall(bytes calldata data) external;

    /// @notice Returns whether this contract implements the given ERC-7579 module type.
    /// @dev    Returns `true` only for type 2 (executor).
    /// @param moduleTypeId The ERC-7579 module type identifier to query.
    /// @return True if moduleTypeId == 2.
    function isModuleType(uint256 moduleTypeId) external pure returns (bool);

    // -------------------------------------------------------------------------
    // Resolver Update Actions
    // -------------------------------------------------------------------------

    /// @notice Updates the ETH address record on the resolver for the caller's node.
    /// @dev    Callable by the installed account (msg.sender must have a stored node).
    ///         Triggers `IResolver.setAddr(node, newAddr)` via `executeFromExecutor`.
    /// @param resolver The address of the khaaliResolver (or compatible) contract.
    /// @param newAddr  The new address to set for the node.
    function updateAddress(address resolver, address newAddr) external;

    /// @notice Updates a text record on the resolver for the caller's node.
    /// @dev    Callable by the installed account (msg.sender must have a stored node).
    ///         Triggers `IResolver.setText(node, key, value)` via `executeFromExecutor`.
    /// @param resolver The address of the khaaliResolver (or compatible) contract.
    /// @param key      The text record key (e.g. "avatar", "pfp", "url").
    /// @param value    The text record value.
    function updateTextRecord(address resolver, string calldata key, string calldata value) external;

    /// @notice Updates the name record on the resolver for the caller's node.
    /// @dev    Callable by the installed account (msg.sender must have a stored node).
    ///         Triggers `IResolver.setName(node, newName)` via `executeFromExecutor`.
    /// @param resolver The address of the khaaliResolver (or compatible) contract.
    /// @param newName  The human-readable name to set for the node.
    function updateName(address resolver, string calldata newName) external;

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------

    /// @notice Returns the RNS node associated with the given account address.
    /// @param account The smart account address to query.
    /// @return node The bytes32 RNS node, or bytes32(0) if not installed.
    function nodeOf(address account) external view returns (bytes32 node);
}
