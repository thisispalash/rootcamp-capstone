// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Receiver} from "solady/accounts/Receiver.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";
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
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external payable returns (uint256) {
        require(hasRole(ENTRYPOINT_ROLE, msg.sender), "khaaliAccount: caller is not entrypoint");

        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.tryRecover(ethSignedHash, userOp.signature);

        if (signer != address(0) && hasRole(OWNER_ROLE, signer)) {
            if (missingAccountFunds > 0) {
                (bool success,) = msg.sender.call{value: missingAccountFunds}("");
                require(success, "khaaliAccount: prefund failed");
            }
            return 0; // SIG_VALIDATION_SUCCESS
        }
        return 1; // SIG_VALIDATION_FAILED
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Execution
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function execute(bytes32 mode, bytes calldata executionData) external payable {
        require(
            hasRole(OWNER_ROLE, msg.sender) || hasRole(ENTRYPOINT_ROLE, msg.sender),
            "khaaliAccount: caller lacks OWNER_ROLE or ENTRYPOINT_ROLE"
        );
        _executeInternal(mode, executionData);
    }

    /// @inheritdoc IkhaaliAccount
    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionData
    ) external returns (bytes[] memory) {
        require(hasRole(MODULE_ROLE, msg.sender), "khaaliAccount: caller lacks MODULE_ROLE");
        return _executeInternalWithReturn(mode, executionData);
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Module Management
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) external {
        require(
            hasRole(OWNER_ROLE, msg.sender) || hasRole(MANAGER_ROLE, msg.sender),
            "khaaliAccount: caller lacks OWNER_ROLE or MANAGER_ROLE"
        );
        _modules[moduleTypeId][module] = true;
        // If executor module (type 2), grant MODULE_ROLE so it can call executeFromExecutor
        if (moduleTypeId == 2) {
            _grantRole(MODULE_ROLE, module);
        }
        // If initData is non-empty, call module.onInstall(initData)
        if (initData.length > 0) {
            (bool success,) = module.call(abi.encodeWithSignature("onInstall(bytes)", initData));
            require(success, "khaaliAccount: onInstall call failed");
        }
        emit ModuleInstalled(moduleTypeId, module);
    }

    /// @inheritdoc IkhaaliAccount
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    ) external {
        require(
            hasRole(OWNER_ROLE, msg.sender) || hasRole(MANAGER_ROLE, msg.sender),
            "khaaliAccount: caller lacks OWNER_ROLE or MANAGER_ROLE"
        );
        _modules[moduleTypeId][module] = false;
        // If executor module (type 2), revoke MODULE_ROLE
        if (moduleTypeId == 2) {
            _revokeRole(MODULE_ROLE, module);
        }
        // If deInitData is non-empty, call module.onUninstall(deInitData)
        if (deInitData.length > 0) {
            (bool success,) = module.call(abi.encodeWithSignature("onUninstall(bytes)", deInitData));
            require(success, "khaaliAccount: onUninstall call failed");
        }
        emit ModuleUninstalled(moduleTypeId, module);
    }

    /// @inheritdoc IkhaaliAccount
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata /*additionalContext*/
    ) external view returns (bool) {
        return _modules[moduleTypeId][module];
    }

    // -------------------------------------------------------------------------
    // ERC-7579 — Account Config
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function accountId() external pure returns (string memory) {
        return "khaali.account.v1";
    }

    /// @inheritdoc IkhaaliAccount
    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        bytes1 callType = LibERC7579.getCallType(mode);
        return callType == LibERC7579.CALLTYPE_SINGLE || callType == LibERC7579.CALLTYPE_BATCH;
    }

    /// @inheritdoc IkhaaliAccount
    function supportsModule(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId >= 1 && moduleTypeId <= 3;
    }

    // -------------------------------------------------------------------------
    // ERC-1271 — Signature Validation
    // -------------------------------------------------------------------------

    /// @inheritdoc IkhaaliAccount
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
        address signer = ECDSA.tryRecover(ethSignedHash, signature);
        if (signer != address(0) && hasRole(OWNER_ROLE, signer)) {
            return bytes4(0x1626ba7e);
        }
        return bytes4(0xffffffff);
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
            || interfaceId == bytes4(0x1626ba7e) // ERC-1271
            || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal Execution Helpers
    // -------------------------------------------------------------------------

    /// @dev Shared execution logic for `execute` (no return values).
    function _executeInternal(bytes32 mode, bytes calldata executionData) internal {
        bytes1 callType = LibERC7579.getCallType(mode);
        if (callType == LibERC7579.CALLTYPE_SINGLE) {
            (address target, uint256 value, bytes calldata data) = LibERC7579.decodeSingle(executionData);
            (bool success,) = target.call{value: value}(data);
            require(success, "khaaliAccount: single execution failed");
        } else if (callType == LibERC7579.CALLTYPE_BATCH) {
            bytes32[] calldata pointers = LibERC7579.decodeBatch(executionData);
            for (uint256 i = 0; i < pointers.length; i++) {
                (address target, uint256 value, bytes calldata data) = LibERC7579.getExecution(pointers, i);
                (bool success,) = target.call{value: value}(data);
                require(success, "khaaliAccount: batch execution failed");
            }
        } else {
            revert("khaaliAccount: unsupported call type");
        }
    }

    /// @dev Shared execution logic for `executeFromExecutor` (returns call results).
    function _executeInternalWithReturn(bytes32 mode, bytes calldata executionData)
        internal
        returns (bytes[] memory results)
    {
        bytes1 callType = LibERC7579.getCallType(mode);
        if (callType == LibERC7579.CALLTYPE_SINGLE) {
            (address target, uint256 value, bytes calldata data) = LibERC7579.decodeSingle(executionData);
            (bool success, bytes memory result) = target.call{value: value}(data);
            require(success, "khaaliAccount: single execution failed");
            results = new bytes[](1);
            results[0] = result;
        } else if (callType == LibERC7579.CALLTYPE_BATCH) {
            bytes32[] calldata pointers = LibERC7579.decodeBatch(executionData);
            results = new bytes[](pointers.length);
            for (uint256 i = 0; i < pointers.length; i++) {
                (address target, uint256 value, bytes calldata data) = LibERC7579.getExecution(pointers, i);
                (bool success, bytes memory result) = target.call{value: value}(data);
                require(success, "khaaliAccount: batch execution failed");
                results[i] = result;
            }
        } else {
            revert("khaaliAccount: unsupported call type");
        }
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
