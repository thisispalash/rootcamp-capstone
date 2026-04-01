// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Milestone} from "../IkhaaliNamesV1.sol";

/// @title IkhaaliAccountFactory
/// @notice Interface for the khaali smart account factory.
///         Deploys accounts via CREATE2, generates human-readable names,
///         registers RNS subnames, and tracks user milestones.
interface IkhaaliAccountFactory {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new smart account is created.
    /// @param account The address of the newly deployed account proxy.
    /// @param owner   The owner of the new account.
    /// @param name    The human-readable name assigned to the account.
    /// @param subnode The RNS subnode (namehash) registered for the account.
    event AccountCreated(
        address indexed account,
        address indexed owner,
        string name,
        bytes32 indexed subnode
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice The generated RNS subname already exists in the registry.
    error NameCollision();

    /// @notice The provided owner address is invalid (e.g. zero address).
    error InvalidOwner();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @notice Deploy a new smart account for the given owner.
    /// @dev Increments userCount, deploys an ERC1967 proxy via CREATE2,
    ///      generates a random name, registers an RNS subname, installs the
    ///      RNS module on the account, and emits {AccountCreated}.
    /// @param owner The address that will own the new account.
    /// @return account The address of the deployed account proxy.
    /// @return name    The human-readable name assigned to the account.
    function createAccount(address owner) external returns (address account, string memory name);

    /// @notice Compute the deterministic CREATE2 address for an account.
    /// @param owner                  The owner address used in the salt.
    /// @param userCountAtDeployment  The userCount value at the time of deployment.
    /// @return The predicted account proxy address.
    function getAddress(address owner, uint256 userCountAtDeployment) external view returns (address);

    /// @notice Returns the current milestone based on userCount.
    /// @return The active Milestone enum value.
    function currentMilestone() external view returns (Milestone);

    /// @notice Returns the total number of accounts created.
    /// @return The current user count.
    function userCount() external view returns (uint256);

    /// @notice Initializes the factory with all required configuration.
    /// @param admin                 The address granted DEFAULT_ADMIN_ROLE.
    /// @param accountImplementation The khaaliAccount implementation address.
    /// @param khaaliNames           The khaaliNamesV1 contract address.
    /// @param rnsRegistry           The RNS registry contract address.
    /// @param resolver              The khaaliResolver contract address.
    /// @param parentNode            The RNS parent node under which subnames are created.
    /// @param rnsModule             The RNSNameModuleV1 contract address.
    function initialize(
        address admin,
        address accountImplementation,
        address khaaliNames,
        address rnsRegistry,
        address resolver,
        bytes32 parentNode,
        address rnsModule
    ) external;
}
