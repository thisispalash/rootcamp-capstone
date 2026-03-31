// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Receiver} from "solady/accounts/Receiver.sol";
import {IkhaaliAccount} from "./IkhaaliAccount.sol";

/// @title khaaliAccount
/// @notice ERC-4337 + ERC-7579 modular smart account implementation.
/// @dev UUPS-upgradeable, role-gated, supports module management stubs (filled in Task 3).
///      Inheritance order: Initializable → UUPSUpgradeable → AccessControlUpgradeable → Receiver → IkhaaliAccount.
///      The constructor disables initializers so the implementation contract cannot be used directly.
contract khaaliAccount is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    Receiver,
    IkhaaliAccount
{

    // -------------------------------------------------------------------------
    // Role constants
    // -------------------------------------------------------------------------

    /// @notice Role for the account owner — can upgrade and manage roles.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @notice Role for an authorised manager — limited admin capability.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role for the ERC-4337 EntryPoint — allowed to call validateUserOp.
    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");

    /// @notice Role for installed modules — granted on install, revoked on uninstall.
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @dev The trusted ERC-4337 EntryPoint address. Set once in the constructor.
    address private immutable _entryPoint;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @dev Module type ID → module address → installed flag.
    /// Using a simple nested mapping avoids the Cancun-only `mcopy` opcode that
    /// OZ v5's EnumerableSet pulls in via Arrays.sol, which would be incompatible
    /// with the project's `evm_version = "london"` setting.
    mapping(uint256 => mapping(address => bool)) private _modules;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param entryPoint_ The immutable ERC-4337 EntryPoint address.
    constructor(address entryPoint_) {
        _entryPoint = entryPoint_;
        _disableInitializers();
    }

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function initialize(address owner, address manager) external initializer {
        __AccessControl_init();

        // Owner receives both DEFAULT_ADMIN_ROLE (manages all roles) and OWNER_ROLE.
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(OWNER_ROLE, owner);

        // Manager receives MANAGER_ROLE.
        _grantRole(MANAGER_ROLE, manager);

        // EntryPoint receives ENTRYPOINT_ROLE so it may call validateUserOp.
        _grantRole(ENTRYPOINT_ROLE, _entryPoint);
    }

    // -------------------------------------------------------------------------
    // ERC-4337 — Account Abstraction
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function entryPoint() external view returns (address) {
        return _entryPoint;
    }

    /// @inheritdoc IkhaaliAccount
    function validateUserOp(
        PackedUserOperation calldata, /*userOp*/
        bytes32, /*userOpHash*/
        uint256 /*missingAccountFunds*/
    ) external payable returns (uint256) {
        revert("not yet implemented");
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Execution
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function execute(bytes32, /*mode*/ bytes calldata /*executionData*/) external payable {
        revert("not yet implemented");
    }

    /// @inheritdoc IkhaaliAccount
    function executeFromExecutor(
        bytes32, /*mode*/
        bytes calldata /*executionData*/
    ) external returns (bytes[] memory) {
        revert("not yet implemented");
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Module Management
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function installModule(
        uint256, /*moduleTypeId*/
        address, /*module*/
        bytes calldata /*initData*/
    ) external {
        revert("not yet implemented");
    }

    /// @inheritdoc IkhaaliAccount
    function uninstallModule(
        uint256, /*moduleTypeId*/
        address, /*module*/
        bytes calldata /*deInitData*/
    ) external {
        revert("not yet implemented");
    }

    /// @inheritdoc IkhaaliAccount
    function isModuleInstalled(
        uint256, /*moduleTypeId*/
        address, /*module*/
        bytes calldata /*additionalContext*/
    ) external view returns (bool) {
        revert("not yet implemented");
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Account Config
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function accountId() external pure returns (string memory) {
        return "khaali.account.v1";
    }

    /// @inheritdoc IkhaaliAccount
    function supportsExecutionMode(bytes32 /*mode*/) external pure returns (bool) {
        revert("not yet implemented");
    }

    /// @inheritdoc IkhaaliAccount
    function supportsModule(uint256 /*moduleTypeId*/) external pure returns (bool) {
        revert("not yet implemented");
    }

    // -------------------------------------------------------------------------
    // ERC-1271 — Signature Validation
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function isValidSignature(
        bytes32, /*hash*/
        bytes calldata /*signature*/
    ) external pure returns (bytes4) {
        revert("not yet implemented");
    }

    // -------------------------------------------------------------------------
    // ERC-165 — Interface Detection
    // -------------------------------------------------------------------------

    /// @notice Returns whether the contract implements a given interface.
    /// @dev Overrides AccessControlUpgradeable's supportsInterface to also handle IkhaaliAccount.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, IkhaaliAccount)
        returns (bool)
    {
        return interfaceId == type(IkhaaliAccount).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // UUPS — Upgrade Authorization
    // -------------------------------------------------------------------------

    /// @dev Only accounts with OWNER_ROLE may authorize an upgrade.
    function _authorizeUpgrade(address /*newImplementation*/) internal override onlyRole(OWNER_ROLE) {}

    // -------------------------------------------------------------------------
    // ETH Receive — provided by Solady Receiver
    // -------------------------------------------------------------------------
    // Solady's Receiver supplies `receive() external payable virtual {}` and a
    // `fallback()` that handles ERC-721 / ERC-1155 safety callbacks. Nothing
    // extra needed here.
}
