// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IkhaaliAccount
/// @notice Interface for the khaali smart account — an ERC-4337 + ERC-7579 modular smart account.
/// @dev Combines ERC-4337 (account abstraction), ERC-7579 (modular account), ERC-1271 (sig validation),
///      and ERC-165 (interface detection). The account is UUPS-upgradeable and role-gated.
interface IkhaaliAccount {

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice Packed user operation as defined by ERC-4337 v0.7.
    struct PackedUserOperation {
        /// @dev The account making the operation.
        address sender;
        /// @dev Anti-replay nonce.
        uint256 nonce;
        /// @dev If set, used to deploy the account before execution.
        bytes initCode;
        /// @dev The call data to execute on the account.
        bytes callData;
        /// @dev Packed gas limits: verificationGasLimit (high 128 bits) | callGasLimit (low 128 bits).
        bytes32 accountGasLimits;
        /// @dev Gas overhead not tracked in the other gas fields.
        uint256 preVerificationGas;
        /// @dev Packed fee info: maxPriorityFeePerGas (high 128 bits) | maxFeePerGas (low 128 bits).
        bytes32 gasFees;
        /// @dev Optional paymaster data — empty if no paymaster.
        bytes paymasterAndData;
        /// @dev Signature over the user operation hash.
        bytes signature;
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a module is installed on the account.
    /// @param moduleTypeId The ERC-7579 module type identifier.
    /// @param module The address of the installed module.
    event ModuleInstalled(uint256 indexed moduleTypeId, address indexed module);

    /// @notice Emitted when a module is uninstalled from the account.
    /// @param moduleTypeId The ERC-7579 module type identifier.
    /// @param module The address of the uninstalled module.
    event ModuleUninstalled(uint256 indexed moduleTypeId, address indexed module);

    // -------------------------------------------------------------------------
    // ERC-4337 — Account Abstraction
    // -------------------------------------------------------------------------

    /// @notice Validates a user operation sent from the EntryPoint.
    /// @dev Called by the EntryPoint during the verification phase of ERC-4337.
    ///      Must return SIG_VALIDATION_SUCCESS (0) or SIG_VALIDATION_FAILED (1),
    ///      optionally packed with a validUntil/validAfter timestamp.
    /// @param userOp The packed user operation.
    /// @param userOpHash The hash of the user operation (for signature verification).
    /// @param missingAccountFunds Prefund to send to the EntryPoint if needed.
    /// @return validationData Encoded validation result.
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external payable returns (uint256 validationData);

    /// @notice Returns the address of the trusted ERC-4337 EntryPoint.
    /// @return The EntryPoint address.
    function entryPoint() external view returns (address);

    // -------------------------------------------------------------------------
    // ERC-7579 — Modular Account Execution
    // -------------------------------------------------------------------------

    /// @notice Executes an operation according to the given execution mode.
    /// @dev Execution modes are defined in ERC-7579 (single, batch, try-mode, delegate, etc.).
    /// @param mode The encoded execution mode.
    /// @param executionData ABI-encoded execution payload.
    function execute(bytes32 mode, bytes calldata executionData) external payable;

    /// @notice Executes an operation on behalf of an executor module.
    /// @dev Only callable by an installed executor module.
    /// @param mode The encoded execution mode.
    /// @param executionData ABI-encoded execution payload.
    /// @return returnData Array of return data from each sub-call.
    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionData
    ) external returns (bytes[] memory returnData);

    // -------------------------------------------------------------------------
    // ERC-7579 — Module Management
    // -------------------------------------------------------------------------

    /// @notice Installs a module of the given type onto the account.
    /// @param moduleTypeId The ERC-7579 module type (e.g. 1=validator, 2=executor, 3=fallback, 4=hook).
    /// @param module The address of the module to install.
    /// @param initData Initialization data forwarded to the module's onInstall hook.
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) external;

    /// @notice Uninstalls a module of the given type from the account.
    /// @param moduleTypeId The ERC-7579 module type.
    /// @param module The address of the module to uninstall.
    /// @param deInitData De-initialization data forwarded to the module's onUninstall hook.
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    ) external;

    /// @notice Returns whether a module of the given type is installed.
    /// @param moduleTypeId The ERC-7579 module type.
    /// @param module The address of the module.
    /// @param additionalContext Optional context used by some module types.
    /// @return True if the module is currently installed.
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    ) external view returns (bool);

    // -------------------------------------------------------------------------
    // ERC-7579 — Account Config
    // -------------------------------------------------------------------------

    /// @notice Returns a human-readable identifier for this account implementation.
    /// @return A string of the form "vendor.account.version".
    function accountId() external view returns (string memory);

    /// @notice Returns whether the account supports the given execution mode.
    /// @param mode The encoded execution mode bytes.
    /// @return True if the mode is supported.
    function supportsExecutionMode(bytes32 mode) external view returns (bool);

    /// @notice Returns whether the account supports a given module type.
    /// @param moduleTypeId The ERC-7579 module type identifier.
    /// @return True if the module type is supported.
    function supportsModule(uint256 moduleTypeId) external view returns (bool);

    // -------------------------------------------------------------------------
    // ERC-1271 — Signature Validation
    // -------------------------------------------------------------------------

    /// @notice Validates an off-chain signature against a hash.
    /// @param hash The message hash that was signed.
    /// @param signature The signature bytes to validate.
    /// @return magicValue `0x1626ba7e` if valid, any other value if invalid.
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4 magicValue);

    // -------------------------------------------------------------------------
    // ERC-165 — Interface Detection
    // -------------------------------------------------------------------------

    /// @notice Returns whether the contract implements a given interface.
    /// @param interfaceId The ERC-165 interface identifier.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    // -------------------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------------------

    /// @notice Initializes the account with an owner and a manager.
    /// @dev Must be called exactly once, immediately after proxy deployment.
    ///      Grants DEFAULT_ADMIN_ROLE + OWNER_ROLE to owner, MANAGER_ROLE to manager,
    ///      and ENTRYPOINT_ROLE to the immutable EntryPoint address.
    /// @param owner The initial owner (receives DEFAULT_ADMIN_ROLE and OWNER_ROLE).
    /// @param manager The initial manager (receives MANAGER_ROLE).
    function initialize(address owner, address manager) external;
}
