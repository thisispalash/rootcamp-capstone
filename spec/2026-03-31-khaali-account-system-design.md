# khaali Account System Design

An on-chain user management system built on ERC-7579 modular smart accounts with ERC-4337 account abstraction, integrated with khaaliNames for random username generation and RIF Name Service (RNS) for on-chain identity.

This is a reference implementation for dApps on Rootstock. Forkers deploy their own factory with their own RNS domain, and the system handles account creation, naming, and identity resolution out of the box.

## Contracts

Four new contracts in `src/account/`:

| Contract | Upgradeability | Purpose |
|----------|----------------|---------|
| khaaliAccount | UUPS (user-controlled) | User's on-chain identity and wallet |
| khaaliAccountFactory | UUPS (admin-controlled) | Deploys accounts, assigns names, manages milestones |
| khaaliResolver | UUPS (admin-controlled) | Forward/reverse name resolution + text records |
| RNSNameModuleV1 | Non-upgradeable (v1, locked) | ERC-7579 executor module for managing RNS records |

Interfaces: `IkhaaliAccount`, `IkhaaliAccountFactory`, `IkhaaliResolver`, `IRNSNameModuleV1`. NatSpec documentation lives in the interfaces, not the implementations.

### File layout

```
src/account/
├── IkhaaliAccount.sol
├── khaaliAccount.sol
├── IkhaaliAccountFactory.sol
├── khaaliAccountFactory.sol
└── modules/
    └── rns/
        ├── IRNSNameModuleV1.sol
        ├── RNSNameModuleV1.sol
        ├── IkhaaliResolver.sol
        └── khaaliResolver.sol
```

## Dependencies

```
forge-std          (existing) -- testing
solady             (existing) -- SSTORE2 (dictionaries), LibERC7579 (mode encoding), Receiver (ETH/token callbacks)
@openzeppelin      (new)      -- UUPSUpgradeable, ERC1967Proxy, ECDSA, ERC165, AccessControl
```

Solady is used only for SSTORE2 (existing dictionary contracts) and LibERC7579 (mode/execution encoding helpers). All new account infrastructure (proxy, access control, signature checking, interface detection) uses OpenZeppelin for consistency across the account system.

## Prerequisites

The dApp deployer must own a top-level RNS domain (e.g. `khaali.rsk`) and transfer ownership of that domain's node to the factory contract after deployment. The factory calls `rnsRegistry.setSubnodeOwner(parentNode, ...)` during account creation, which requires it to be the owner of `parentNode` in the RNS registry.

## Account creation flow

The factory uses an atomic deploy-and-initialize pattern: the proxy constructor receives initialization calldata so deployment and initialization happen in a single transaction, preventing front-running of the `initialize` call.

Note: the account address is deterministic (predictable via `getAddress` before deployment), but the name is not -- khaaliNames uses `block.difficulty` and `block.timestamp` as randomness sources, so the generated name depends on which block the transaction lands in.

```
EOA (user's wallet)
 |
 +---> khaaliAccountFactory.createAccount(owner)
 |       1. Increment userCount
 |       2. Compute deterministic salt from owner + userCount
 |       3. Deploy khaaliAccount as ERC1967 proxy via CREATE2
 |          (atomic: proxy constructor calls initialize)
 |       4. account.initialize(owner, address(this)) grants:
 |          - OWNER_ROLE to owner EOA
 |          - ENTRYPOINT_ROLE to the EntryPoint (immutable in impl)
 |          - MANAGER_ROLE to msg.sender (the factory)
 |       5. Call khaaliNames.getRandomName(account, currentMilestone())
 |       6. Compute label = keccak256(name), subnode = keccak256(parentNode, label)
 |       7. Check subnode is not already registered (revert if collision)
 |       8. Call rnsRegistry.setSubnodeOwner(parentNode, label, address(this))
 |       9. Call rnsRegistry.setResolver(subnode, resolver)
 |      10. Call resolver.setAddr(subnode, account) -- forward resolution
 |      11. Call resolver.setName(reverseNode, name) -- reverse resolution
 |      12. Call resolver.setText(subnode, "displayName", name) -- default text record
 |      13. Call rnsRegistry.setOwner(subnode, account) -- transfer ownership to account
 |      14. Call account.installModule(2, rnsModule, abi.encode(subnode))
 |      15. Emit AccountCreated(account, owner, name, subnode)
 |
 +---> khaaliAccount (via 4337 UserOp or direct call)
         +-- execute(...) -- general transactions
         +-- RNSNameModule.updateTextRecord(resolver, "pfp", "ipfs://...")
              +-- calls khaaliResolver.setText(node, key, value)
```

## khaaliAccount

ERC-4337 smart account with ERC-7579 modular extensions and ECDSA owner validation.

### Inheritance

```
khaaliAccount
  +-- UUPSUpgradeable (OZ)
  +-- ERC165 (OZ)
  +-- AccessControl (OZ)
  +-- Receiver (Solady -- ETH/ERC721/ERC1155 receive hooks)
```

The `fallback()` function from Solady's Receiver is overridden: it first checks if there is an installed fallback handler module (type 3) for the incoming selector. If found, the call is delegated to that module. If no fallback module handles the selector, it falls through to Receiver's default behavior (accepts ETH, ERC721, ERC1155 callbacks; reverts on unknown selectors).

### Roles

| Role | Granted to | Permissions |
|------|-----------|-------------|
| OWNER_ROLE | User's EOA | Everything: execute, manage modules, upgrade, grant/revoke roles |
| MANAGER_ROLE | dApp / factory | Install/uninstall modules only |
| ENTRYPOINT_ROLE | 4337 EntryPoint | Call validateUserOp, execute |
| MODULE_ROLE | Installed executor modules | Call executeFromExecutor only |

OWNER_ROLE is the DEFAULT_ADMIN_ROLE. Only the owner can grant/revoke other roles. The owner can revoke MANAGER_ROLE for full sovereignty. dApps that need broader manager authority can extend this in their fork.

### ERC-4337 (implemented from scratch)

- `validateUserOp(PackedUserOperation, bytes32 userOpHash, uint256 missingAccountFunds) payable` -- validates ECDSA signature against owner, pays prefund to EntryPoint
- `entryPoint()` -- returns canonical EntryPoint address (immutable, set in implementation constructor, shared by all proxies)

The EntryPoint address is immutable in the implementation bytecode, not per-proxy. This is the standard ERC-4337 pattern -- all accounts using the same implementation share the same EntryPoint. If Rootstock does not have the canonical ERC-4337 EntryPoint v0.7 deployed, a custom deployment may be needed. The account also works without 4337 via direct EOA calls from the owner.

### ERC-7579

Execution:
- `execute(bytes32 mode, bytes calldata executionData) payable` -- single/batch execution, callable by EntryPoint or owner
- `executeFromExecutor(bytes32 mode, bytes calldata executionData)` -- callback for executor modules, restricted to MODULE_ROLE

Module management:
- `installModule(uint256 moduleTypeId, address module, bytes calldata initData)` -- restricted to OWNER_ROLE and MANAGER_ROLE. Grants MODULE_ROLE to executor modules on install.
- `uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData)` -- restricted to OWNER_ROLE and MANAGER_ROLE. Revokes MODULE_ROLE from executor modules on uninstall.
- `isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext)` -- public view

Account config:
- `accountId()` -- returns `"khaali.account.v1"`
- `supportsExecutionMode(bytes32)` -- reports supported modes (single, batch)
- `supportsModule(uint256)` -- reports supported module types (1: validator, 2: executor, 3: fallback handler)

### Module storage

```solidity
mapping(uint256 => EnumerableSet.AddressSet) private _modules;
```

Uses OpenZeppelin's `EnumerableSet.AddressSet`. Supports module types 1 (validator), 2 (executor), 3 (fallback handler). Hooks (type 4) omitted -- forkers can add them.

### ERC-1271

`isValidSignature(bytes32 hash, bytes calldata signature)` -- checks ECDSA against the owner address, returns the ERC-1271 magic value. Enables dApps to verify the account owner signed a message.

### ERC-165

`supportsInterface(bytes4)` reports support for: IERC7579Account, IAccount (ERC-4337), IERC1271, IERC165, IAccessControl.

### Initialization

```solidity
function initialize(address owner, address manager) external initializer
```

Called atomically during proxy deployment. Grants OWNER_ROLE (= DEFAULT_ADMIN_ROLE) to the EOA, ENTRYPOINT_ROLE to the immutable EntryPoint, and MANAGER_ROLE to `manager` (the factory). The EntryPoint is not a parameter because it is immutable in the implementation.

### LibERC7579 usage

Used for decoding the `bytes32 mode` field (call type, exec type) and decoding execution calldata (single vs batch). No reimplementation.

## khaaliAccountFactory

Deploys accounts, generates names via khaaliNames, registers RNS subnames, and tracks growth milestones.

### Inheritance

```
khaaliAccountFactory
  +-- UUPSUpgradeable (OZ)
  +-- AccessControl (OZ)
  +-- ERC165 (OZ)
```

### Roles

- ADMIN_ROLE -- dApp deployer. Can upgrade, update config.

`createAccount` is permissionless (anyone can call).

### State

```solidity
address public accountImplementation; // khaaliAccount impl for proxies (storage, not immutable)
address public khaaliNames;           // khaaliNamesV1 address
address public rnsRegistry;           // RNS registry address
address public resolver;              // khaaliResolver address
bytes32 public parentNode;            // namehash of top-level domain
address public rnsModule;             // RNSNameModuleV1 address

uint256 public userCount;             // total accounts created
```

`accountImplementation` is a storage variable (not `immutable`) so it survives factory upgrades. When upgrading the factory implementation, the stored reference to the account implementation persists in proxy storage.

### Initialization

```solidity
function initialize(
    address admin,
    address _accountImplementation,
    address _khaaliNames,
    address _rnsRegistry,
    address _resolver,
    bytes32 _parentNode,
    address _rnsModule
) external initializer
```

Grants ADMIN_ROLE to the deployer. Sets all configuration addresses.

### Milestone logic

```solidity
function currentMilestone() public view returns (Milestone) {
    if (userCount < 10_000)    return Milestone.ANIMAL_30;
    if (userCount < 100_000)   return Milestone.COLOR_ANIMAL_5;
    if (userCount < 1_000_000) return Milestone.ADJ_ANIMAL_2;
    return Milestone.ADJ_COLOR_ANIMAL_3;
}
```

Milestones are dApp-level, not per-user. The milestone determines name complexity based on total user count. Shorter names signify earlier adoption.

- ANIMAL_30: 350 animals x 30 suffixes = ~10k users
- COLOR_ANIMAL_5: 50 colors x 350 animals x 5 suffixes = ~87k users
- ADJ_ANIMAL_2: 1200 adjectives x 350 animals x 2 suffixes = ~840k users
- ADJ_COLOR_ANIMAL_3: 1200 x 50 x 350 x 3 = ~63m users

### Name collision handling

khaaliNames generates pseudo-random names from `address + block data`. Collisions are theoretically possible. The factory checks if the subname already exists in the RNS registry and reverts with a retry-friendly error if so. The caller retries in a different block (different seed).

### Deterministic addresses

`getAddress(address owner, uint256 userCountAtDeployment)` predicts the account address before deployment. The second parameter corresponds to the factory's `userCount` at the time of deployment -- callers must read `userCount` to predict the correct salt. Useful for counterfactual accounts in ERC-4337.

## khaaliResolver

Shared resolver for all subnames under the dApp's domain. Handles forward resolution, reverse resolution, and text records.

### Inheritance

```
khaaliResolver
  +-- UUPSUpgradeable (OZ)
  +-- AccessControl (OZ)
  +-- ERC165 (OZ)
```

### Roles

- ADMIN_ROLE -- deployer, can upgrade
- OPERATOR_ROLE -- the factory, can set records during account creation

Record owners (the account that owns the subname) can always update their own records. No role needed -- verified by checking `rnsRegistry.owner(node)`.

### Initialization

```solidity
function initialize(address admin, address operator, address _rnsRegistry) external initializer
```

Grants ADMIN_ROLE to the deployer, OPERATOR_ROLE to the factory. Sets the RNS registry address.

### Storage

```solidity
address public rnsRegistry;

mapping(bytes32 => address) private _addresses;              // node -> address
mapping(bytes32 => string) private _names;                   // reverse node -> name
mapping(bytes32 => mapping(string => string)) private _texts; // node -> key -> value
```

### Write functions

All guarded by `onlyNodeOwnerOrOperator`: checks `msg.sender == rnsRegistry.owner(node) || hasRole(OPERATOR_ROLE, msg.sender)`.

```solidity
function setAddr(bytes32 node, address addr) external;
function setName(bytes32 node, string calldata name) external;
function setText(bytes32 node, string calldata key, string calldata value) external;
```

### Read functions

```solidity
function addr(bytes32 node) external view returns (address);   // EIP-137
function name(bytes32 node) external view returns (string);    // reverse resolution
function text(bytes32 node, string calldata key) external view returns (string); // EIP-634
```

### ERC-165

Reports support for interface IDs: `addr(bytes32)` (0x3b3b57de), `name(bytes32)` (0x691f3431), `text(bytes32,string)` (0x59d1d43c).

### Reverse resolution

RNS reverse resolution follows the ENS/EIP-137 convention. The reverse node for an address is computed as:

```
ADDR_REVERSE_NODE = namehash("addr.reverse")
reverseNode = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, keccak256(bytes(lowerHexWithout0x(account)))))
```

Where `lowerHexWithout0x` converts the address to a lowercase hex string without the "0x" prefix (e.g. `0xAbC...` becomes `"abc..."`). This matches the standard ENS/RNS reverse registrar convention. The factory computes this during account creation and calls `setName` on it.

## RNSNameModuleV1

ERC-7579 executor module that lets accounts manage their own RNS records after creation.

### Interface

Implements `IERC7579Module`: `onInstall`, `onUninstall`, `isModuleType`. Reports as module type 2 (executor).

### Storage

```solidity
mapping(address => bytes32) private _nodes; // account -> subnode
```

### Lifecycle

```solidity
function onInstall(bytes calldata data) external {
    // decode subnode, store: _nodes[msg.sender] = subnode
}

function onUninstall(bytes calldata data) external {
    // delete _nodes[msg.sender]
}
```

### User-facing functions

```solidity
function updateAddress(address resolver, address newAddr) external;
function updateTextRecord(address resolver, string calldata key, string calldata value) external;
function updateName(address resolver, string calldata newName) external;
function nodeOf(address account) external view returns (bytes32);
```

Note: `updateAddress` updates only the forward resolution record. Reverse resolution is a separate operation via `updateName`. This is intentional -- the user may want to point their name at a different address without changing the reverse mapping, or vice versa.

### Executor callback pattern

The module calls back into the account via `executeFromExecutor` so the account is always `msg.sender` to the resolver. This satisfies the resolver's ownership check.

```
Account.execute(...)
  -> RNSNameModuleV1.updateTextRecord(resolver, "pfp", "ipfs://...")
    -> Account.executeFromExecutor(...)
      -> khaaliResolver.setText(node, "pfp", "ipfs://...") // msg.sender = account
```

### Exclusions

No name transfer/trading logic. No subname registration (factory handles that). No milestone upgrades.

## Interfaces

All NatSpec documentation lives in these interfaces. Events are defined here alongside function signatures.

### IkhaaliAccount

```solidity
// Events
event ModuleInstalled(uint256 indexed moduleTypeId, address indexed module);
event ModuleUninstalled(uint256 indexed moduleTypeId, address indexed module);

// ERC-4337
function validateUserOp(PackedUserOperation calldata, bytes32, uint256) external payable returns (uint256);
function entryPoint() external view returns (address);

// ERC-7579 execution
function execute(bytes32 mode, bytes calldata executionData) external payable;
function executeFromExecutor(bytes32 mode, bytes calldata executionData) external returns (bytes[] memory);

// ERC-7579 module management
function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external;
function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external;
function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) external view returns (bool);

// ERC-7579 account config
function accountId() external view returns (string memory);
function supportsExecutionMode(bytes32 mode) external view returns (bool);
function supportsModule(uint256 moduleTypeId) external view returns (bool);

// ERC-1271
function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);

// ERC-165
function supportsInterface(bytes4 interfaceId) external view returns (bool);

// Initialization
function initialize(address owner, address manager) external;
```

### IkhaaliAccountFactory

```solidity
// Events
event AccountCreated(address indexed account, address indexed owner, string name, bytes32 indexed subnode);

// Core
function createAccount(address owner) external returns (address account, string memory name);
function getAddress(address owner, uint256 userCountAtDeployment) external view returns (address);
function currentMilestone() external view returns (Milestone);
function userCount() external view returns (uint256);

// Initialization
function initialize(
    address admin,
    address accountImplementation,
    address khaaliNames,
    address rnsRegistry,
    address resolver,
    bytes32 parentNode,
    address rnsModule
) external;
```

### IkhaaliResolver

```solidity
// Events
event AddrChanged(bytes32 indexed node, address addr);
event NameChanged(bytes32 indexed node, string name);
event TextChanged(bytes32 indexed node, string indexed indexedKey, string key, string value);

// Write
function setAddr(bytes32 node, address addr) external;
function setName(bytes32 node, string calldata name) external;
function setText(bytes32 node, string calldata key, string calldata value) external;

// Read
function addr(bytes32 node) external view returns (address);
function name(bytes32 node) external view returns (string memory);
function text(bytes32 node, string calldata key) external view returns (string memory);

// Initialization
function initialize(address admin, address operator, address rnsRegistry) external;
```

### IRNSNameModuleV1

Extends `IERC7579Module` (`onInstall`, `onUninstall`, `isModuleType`) with the following:

```solidity
// Events
event NodeSet(address indexed account, bytes32 indexed node);
event NodeCleared(address indexed account);

// User-facing
function updateAddress(address resolver, address newAddr) external;
function updateTextRecord(address resolver, string calldata key, string calldata value) external;
function updateName(address resolver, string calldata newName) external;
function nodeOf(address account) external view returns (bytes32);
```

## Testing

Foundry tests following the existing pattern in `khaaliNamesV1.t.sol`.

### File structure

```
test/
├── khaaliNamesV1.t.sol          (existing)
├── khaaliAccount.t.sol
├── khaaliAccountFactory.t.sol
├── khaaliResolver.t.sol
└── RNSNameModuleV1.t.sol
```

### khaaliAccount.t.sol

- Initialization: owner gets OWNER_ROLE, manager gets MANAGER_ROLE, can't re-initialize
- Execute: owner can execute single/batch calls, unauthorized callers revert
- Module management: install/uninstall executors, query isModuleInstalled, only OWNER_ROLE and MANAGER_ROLE can manage modules
- MODULE_ROLE: granted on install, revoked on uninstall
- ERC-1271: valid owner signature returns magic value, invalid reverts
- ERC-165: reports correct interface IDs
- UUPS: owner can upgrade, non-owner can't
- executeFromExecutor: only installed executor modules (MODULE_ROLE) can call
- Fallback handler: installed fallback module receives unknown selector calls

### khaaliAccountFactory.t.sol

- Initialization: admin role set, all config addresses stored correctly
- createAccount: deploys account, generates name, registers subname, installs module
- Deterministic addresses: getAddress matches actual deployment
- Milestone progression: userCount thresholds switch milestones correctly
- Name collision: reverts cleanly if subname already taken
- RNS integration: subname ownership transferred to account, resolver set correctly
- MANAGER_ROLE: factory has MANAGER_ROLE on created accounts

### khaaliResolver.t.sol

- Initialization: admin and operator roles set correctly
- Read/write: setAddr/addr, setName/name, setText/text round-trip correctly
- Access control: node owner can update, operator can update, random address reverts
- Events: AddrChanged, NameChanged, TextChanged emitted correctly
- ERC-165: reports correct interface IDs

### RNSNameModuleV1.t.sol

- Install/uninstall: stores and clears node correctly
- Update flows: updateTextRecord calls back through account to resolver, record is updated
- Authorization: only installed on the account, reverts if not installed
- updateAddress vs updateName: forward and reverse records updated independently

### RNS mocking

Tests use a mock RNS registry implementing the AbstractRNS interface. Keeps tests fast and self-contained without depending on RSK testnet state.
