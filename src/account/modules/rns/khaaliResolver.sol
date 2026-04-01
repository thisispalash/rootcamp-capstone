// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IkhaaliResolver} from "./IkhaaliResolver.sol";

interface IRNSRegistry {
    function owner(bytes32 node) external view returns (address);
}

contract khaaliResolver is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    IkhaaliResolver
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IRNSRegistry public rnsRegistry;

    mapping(bytes32 => address) private _addresses;
    mapping(bytes32 => string) private _names;
    mapping(bytes32 => mapping(string => string)) private _texts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address operator, address _rnsRegistry) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
        rnsRegistry = IRNSRegistry(_rnsRegistry);
    }

    // --- Write --- //

    function setAddr(bytes32 node, address _addr) external {
        _checkAuthorized(node);
        _addresses[node] = _addr;
        emit AddrChanged(node, _addr);
    }

    function setName(bytes32 node, string calldata _name) external {
        _checkAuthorized(node);
        _names[node] = _name;
        emit NameChanged(node, _name);
    }

    function setText(bytes32 node, string calldata key, string calldata value) external {
        _checkAuthorized(node);
        _texts[node][key] = value;
        emit TextChanged(node, key, key, value);
    }

    // --- Read --- //

    function addr(bytes32 node) external view returns (address) {
        return _addresses[node];
    }

    function name(bytes32 node) external view returns (string memory) {
        return _names[node];
    }

    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }

    // --- ERC-165 --- //

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == 0x3b3b57de  // addr(bytes32)
            || interfaceId == 0x691f3431  // name(bytes32)
            || interfaceId == 0x59d1d43c  // text(bytes32,string)
            || super.supportsInterface(interfaceId);
    }

    // --- Internal --- //

    function _checkAuthorized(bytes32 node) internal view {
        if (msg.sender != rnsRegistry.owner(node) && !hasRole(OPERATOR_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
