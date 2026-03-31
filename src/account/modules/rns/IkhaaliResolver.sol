// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IkhaaliResolver
/// @notice Interface for the khaali RNS resolver.
///         Supports forward resolution (EIP-137), reverse resolution,
///         and text records (EIP-634).
interface IkhaaliResolver {

    // --- Events --- //

    /// @notice Emitted when a node's address record is updated.
    event AddrChanged(bytes32 indexed node, address addr);

    /// @notice Emitted when a node's name record is updated (reverse resolution).
    event NameChanged(bytes32 indexed node, string name);

    /// @notice Emitted when a node's text record is updated.
    event TextChanged(bytes32 indexed node, string indexed indexedKey, string key, string value);

    // --- Errors --- //

    /// @notice Caller is neither the node owner nor an operator.
    error NotAuthorized();

    // --- Write --- //

    /// @notice Set the address record for a node.
    /// @param node The namehash of the domain.
    /// @param addr The address to resolve to.
    function setAddr(bytes32 node, address addr) external;

    /// @notice Set the name record for a node (used for reverse resolution).
    /// @param node The reverse node hash.
    /// @param name The human-readable name.
    function setName(bytes32 node, string calldata name) external;

    /// @notice Set a text record for a node.
    /// @param node The namehash of the domain.
    /// @param key The text record key (e.g. "displayName", "pfp").
    /// @param value The text record value.
    function setText(bytes32 node, string calldata key, string calldata value) external;

    // --- Read --- //

    /// @notice Get the address record for a node (EIP-137).
    function addr(bytes32 node) external view returns (address);

    /// @notice Get the name record for a node (reverse resolution).
    function name(bytes32 node) external view returns (string memory);

    /// @notice Get a text record for a node (EIP-634).
    function text(bytes32 node, string calldata key) external view returns (string memory);

    // --- Initialization --- //

    /// @notice Initialize the resolver with admin, operator, and RNS registry.
    /// @param admin The address granted ADMIN_ROLE (can upgrade).
    /// @param operator The address granted OPERATOR_ROLE (factory, can set records).
    /// @param rnsRegistry The RNS registry contract address.
    function initialize(address admin, address operator, address rnsRegistry) external;
}
