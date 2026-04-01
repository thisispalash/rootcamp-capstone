// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IkhaaliAccountFactory} from "./IkhaaliAccountFactory.sol";
import {IkhaaliAccount} from "./IkhaaliAccount.sol";
import {IkhaaliNamesV1, Milestone} from "../IkhaaliNamesV1.sol";
import {IkhaaliResolver} from "./modules/rns/IkhaaliResolver.sol";

interface IRNSRegistry {
    function owner(bytes32 node) external view returns (address);
    function setSubnodeOwner(bytes32 node, bytes32 label, address newOwner) external returns (bytes32);
    function setResolver(bytes32 node, address resolver) external;
    function setOwner(bytes32 node, address newOwner) external;
}

/// @title khaaliAccountFactory
/// @notice UUPS-upgradeable factory that deploys khaali smart accounts,
///         generates human-readable names, and registers RNS subnames.
/// @dev Uses CREATE2 for deterministic deployment. AccessControl-gated.
contract khaaliAccountFactory is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    IkhaaliAccountFactory
{

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice The khaaliAccount implementation contract used for ERC1967 proxies.
    address public accountImplementation;

    /// @notice The khaaliNamesV1 contract for generating random names.
    address public khaaliNames;

    /// @notice The RNS registry contract.
    address public rnsRegistry;

    /// @notice The khaaliResolver contract.
    address public resolver;

    /// @notice The RNS parent node under which subnames are created.
    bytes32 public parentNode;

    /// @notice The RNSNameModuleV1 contract address.
    address public rnsModule;

    /// @notice The total number of accounts created.
    uint256 public userCount;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccountFactory
    function initialize(
        address admin,
        address _accountImplementation,
        address _khaaliNames,
        address _rnsRegistry,
        address _resolver,
        bytes32 _parentNode,
        address _rnsModule
    ) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        accountImplementation = _accountImplementation;
        khaaliNames = _khaaliNames;
        rnsRegistry = _rnsRegistry;
        resolver = _resolver;
        parentNode = _parentNode;
        rnsModule = _rnsModule;
    }

    // -------------------------------------------------------------------------
    // Milestone
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccountFactory
    function currentMilestone() public view returns (Milestone) {
        if (userCount < 10_000)    return Milestone.ANIMAL_30;
        if (userCount < 100_000)   return Milestone.COLOR_ANIMAL_5;
        if (userCount < 1_000_000) return Milestone.ADJ_ANIMAL_2;
        return Milestone.ADJ_COLOR_ANIMAL_3;
    }

    // -------------------------------------------------------------------------
    // Account Creation
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccountFactory
    function createAccount(address owner) external returns (address account, string memory name) {
        if (owner == address(0)) revert InvalidOwner();

        // 1. Increment user count
        userCount++;

        // 2. Compute salt
        bytes32 salt = keccak256(abi.encodePacked(owner, userCount));

        // 3. Deploy proxy via CREATE2
        bytes memory initData = abi.encodeCall(IkhaaliAccount.initialize, (owner, address(this)));
        account = address(new ERC1967Proxy{salt: salt}(accountImplementation, initData));

        // 4. Generate random name
        name = IkhaaliNamesV1(khaaliNames).getRandomName(account, currentMilestone());

        // 5. Compute label and subnode
        bytes32 label = keccak256(bytes(name));
        bytes32 subnode = keccak256(abi.encodePacked(parentNode, label));

        // 6. Check collision
        if (IRNSRegistry(rnsRegistry).owner(subnode) != address(0)) revert NameCollision();

        // 7. Create subnode owned by factory
        IRNSRegistry(rnsRegistry).setSubnodeOwner(parentNode, label, address(this));

        // 8. Set resolver for the subnode
        IRNSRegistry(rnsRegistry).setResolver(subnode, resolver);

        // 9. Forward resolution — name → address
        IkhaaliResolver(resolver).setAddr(subnode, account);

        // 10. Reverse resolution — address → name
        IkhaaliResolver(resolver).setName(_reverseNode(account), name);

        // 11. Text record — displayName
        IkhaaliResolver(resolver).setText(subnode, "displayName", name);

        // 12. Transfer subnode ownership to the account
        IRNSRegistry(rnsRegistry).setOwner(subnode, account);

        // 13. Install RNS module on the account
        IkhaaliAccount(account).installModule(2, rnsModule, abi.encode(subnode));

        // 14. Emit event
        emit AccountCreated(account, owner, name, subnode);

        // 15. Return
        return (account, name);
    }

    // -------------------------------------------------------------------------
    // Address Prediction
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccountFactory
    function getAddress(address owner, uint256 userCountAtDeployment) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(owner, userCountAtDeployment));
        bytes memory initData = abi.encodeCall(IkhaaliAccount.initialize, (owner, address(this)));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(accountImplementation, initData))
        );
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Computes the reverse node for an address following ENS/RNS convention.
    ///      reverse node = keccak256(ADDR_REVERSE_NODE, keccak256(hexAddress))
    function _reverseNode(address addr) internal pure returns (bytes32) {
        bytes32 ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
        return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, keccak256(bytes(_addressToHexString(addr)))));
    }

    /// @dev Converts an address to its lowercase hex string (without 0x prefix).
    function _addressToHexString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        bytes16 hexChars = "0123456789abcdef";
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) >> (8 * (19 - i)));
            s[i * 2] = hexChars[b >> 4];
            s[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return string(s);
    }

    // -------------------------------------------------------------------------
    // UUPS
    // -------------------------------------------------------------------------

    /// @dev Only accounts with DEFAULT_ADMIN_ROLE may authorize an upgrade.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
