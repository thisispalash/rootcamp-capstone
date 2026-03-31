// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Minimal mock of the RNS Registry for testing.
///      Implements owner, resolver, setSubnodeOwner, setResolver, setOwner.
contract MockRNSRegistry {
    struct Record {
        address owner;
        address resolver;
    }

    mapping(bytes32 => Record) private _records;

    constructor() {
        // root node owned by deployer
        _records[bytes32(0)].owner = msg.sender;
    }

    /// @dev Test-only: force-set owner of any node (bypasses ownership check).
    function forceSetOwner(bytes32 node, address newOwner) external {
        _records[node].owner = newOwner;
    }

    function owner(bytes32 node) external view returns (address) {
        return _records[node].owner;
    }

    function resolver(bytes32 node) external view returns (address) {
        return _records[node].resolver;
    }

    function setOwner(bytes32 node, address newOwner) external {
        require(msg.sender == _records[node].owner, "not owner");
        _records[node].owner = newOwner;
    }

    function setSubnodeOwner(bytes32 node, bytes32 label, address newOwner) external returns (bytes32) {
        require(msg.sender == _records[node].owner, "not owner");
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        _records[subnode].owner = newOwner;
        return subnode;
    }

    function setResolver(bytes32 node, address newResolver) external {
        require(msg.sender == _records[node].owner, "not owner");
        _records[node].resolver = newResolver;
    }
}
