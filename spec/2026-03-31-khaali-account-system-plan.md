# khaali Account System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an ERC-7579 modular smart account system with ERC-4337 support, integrated with khaaliNames and RNS for on-chain user identity on Rootstock.

**Architecture:** Four contracts (khaaliAccount, khaaliAccountFactory, khaaliResolver, RNSNameModuleV1) built bottom-up. The resolver and account are independent; the module depends on both; the factory orchestrates everything. UUPS proxies for the three stateful contracts, v1-locked for the module.

**Tech Stack:** Solidity 0.8.28, Foundry (forge), OpenZeppelin (AccessControl, UUPSUpgradeable, ERC1967Proxy, ECDSA, ERC165, EnumerableSet), Solady (LibERC7579, Receiver), existing khaaliNamesV1.

**Spec:** `spec/2026-03-31-khaali-account-system-design.md`

**Conventions (from existing codebase):**
- License: `// SPDX-License-Identifier: MIT`
- Pragma: `pragma solidity ^0.8.28;`
- Test contract naming: `<ContractName>Test is Test`
- Test function naming: `test_<category>_<behavior>`
- NatSpec in interfaces only, not implementations
- camelCase contract names with lowercase `k` for khaali prefix

---

## Task 0: Project Setup

**Files:**
- Modify: `remappings.txt`
- Modify: `foundry.toml`
- Create: `src/account/` directory structure
- Create: `test/mocks/MockRNSRegistry.sol`
- Create: `test/mocks/MockEntryPoint.sol`

- [ ] **Step 1: Install OpenZeppelin contracts (both standard and upgradeable)**

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
```

- [ ] **Step 2: Update remappings.txt**

```
forge-std/=lib/forge-std/src/
solady/=lib/solady/src/
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
```

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p src/account/modules/rns
mkdir -p test/mocks
```

- [ ] **Step 4: Create MockRNSRegistry**

This mock implements the RNS registry interface needed by all tests. Follows the AbstractRNS pattern from RNS.

```solidity
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
```

- [ ] **Step 5: Create MockEntryPoint**

Minimal mock for ERC-4337 EntryPoint. Only needs to exist as an address for role-granting and to call `validateUserOp`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Minimal mock EntryPoint for testing ERC-4337 account validation.
contract MockEntryPoint {
    // Allows test to call validateUserOp on the account as the EntryPoint
    function validateUserOp(
        address account,
        bytes calldata callData
    ) external returns (uint256) {
        (bool success, bytes memory ret) = account.call(callData);
        require(success, "validateUserOp failed");
        return abi.decode(ret, (uint256));
    }
}
```

- [ ] **Step 6: Verify setup compiles**

```bash
forge build
```

Expected: compiles with no errors (mocks only, no imports of unwritten contracts yet).

- [ ] **Step 7: Commit**

```bash
git add remappings.txt foundry.toml src/account/ test/mocks/
git commit -m "chore: setup account system — OZ dep, directory structure, test mocks"
```

---

## Task 1: IkhaaliResolver + khaaliResolver

The resolver is independent of the account contracts, so we build it first.

**Files:**
- Create: `src/account/modules/rns/IkhaaliResolver.sol`
- Create: `src/account/modules/rns/khaaliResolver.sol`
- Create: `test/khaaliResolver.t.sol`

- [ ] **Step 1: Write IkhaaliResolver interface**

```solidity
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
```

- [ ] **Step 2: Write resolver tests**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliResolver} from "../src/account/modules/rns/khaaliResolver.sol";
import {IkhaaliResolver} from "../src/account/modules/rns/IkhaaliResolver.sol";
import {MockRNSRegistry} from "./mocks/MockRNSRegistry.sol";

contract khaaliResolverTest is Test {

    khaaliResolver public resolverImpl;
    khaaliResolver public resolver;
    MockRNSRegistry public registry;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address nodeOwner = makeAddr("nodeOwner");
    address stranger = makeAddr("stranger");

    bytes32 constant TEST_NODE = keccak256("test.node");
    bytes32 constant REVERSE_NODE = keccak256("reverse.node");

    function setUp() public {
        registry = new MockRNSRegistry();

        // Use forceSetOwner to set nodeOwner as owner of TEST_NODE and REVERSE_NODE.
        // In production, ownership comes from setSubnodeOwner (which computes subnodes).
        // For unit tests, we directly assign ownership to known node hashes.
        registry.forceSetOwner(TEST_NODE, nodeOwner);
        registry.forceSetOwner(REVERSE_NODE, nodeOwner);

        resolverImpl = new khaaliResolver();
        bytes memory initData = abi.encodeCall(
            khaaliResolver.initialize,
            (admin, operator, address(registry))
        );
        resolver = khaaliResolver(address(new ERC1967Proxy(address(resolverImpl), initData)));
    }

    // --- Initialization --- //

    function test_init_adminRole() public view {
        assertTrue(resolver.hasRole(resolver.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_init_operatorRole() public view {
        assertTrue(resolver.hasRole(resolver.OPERATOR_ROLE(), operator));
    }

    function test_init_cannotReinitialize() public {
        vm.expectRevert();
        resolver.initialize(admin, operator, address(registry));
    }

    // --- setAddr / addr --- //

    function test_setAddr_byNodeOwner() public {
        address target = makeAddr("target");
        vm.prank(nodeOwner);
        resolver.setAddr(TEST_NODE, target);
        assertEq(resolver.addr(TEST_NODE), target);
    }

    function test_setAddr_byOperator() public {
        address target = makeAddr("target");
        vm.prank(operator);
        resolver.setAddr(TEST_NODE, target);
        assertEq(resolver.addr(TEST_NODE), target);
    }

    function test_setAddr_emitsEvent() public {
        address target = makeAddr("target");
        vm.prank(nodeOwner);
        vm.expectEmit(true, false, false, true);
        emit IkhaaliResolver.AddrChanged(TEST_NODE, target);
        resolver.setAddr(TEST_NODE, target);
    }

    function test_setAddr_revertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(IkhaaliResolver.NotAuthorized.selector);
        resolver.setAddr(TEST_NODE, stranger);
    }

    // --- setName / name --- //

    function test_setName_byNodeOwner() public {
        vm.prank(nodeOwner);
        resolver.setName(REVERSE_NODE, "amber-fox-42");
        assertEq(resolver.name(REVERSE_NODE), "amber-fox-42");
    }

    function test_setName_byOperator() public {
        vm.prank(operator);
        resolver.setName(REVERSE_NODE, "amber-fox-42");
        assertEq(resolver.name(REVERSE_NODE), "amber-fox-42");
    }

    function test_setName_emitsEvent() public {
        vm.prank(nodeOwner);
        vm.expectEmit(true, false, false, true);
        emit IkhaaliResolver.NameChanged(REVERSE_NODE, "amber-fox-42");
        resolver.setName(REVERSE_NODE, "amber-fox-42");
    }

    // --- setText / text --- //

    function test_setText_byNodeOwner() public {
        vm.prank(nodeOwner);
        resolver.setText(TEST_NODE, "displayName", "amber-fox-42");
        assertEq(resolver.text(TEST_NODE, "displayName"), "amber-fox-42");
    }

    function test_setText_multipleKeys() public {
        vm.prank(nodeOwner);
        resolver.setText(TEST_NODE, "displayName", "amber-fox-42");
        vm.prank(nodeOwner);
        resolver.setText(TEST_NODE, "pfp", "ipfs://Qm...");
        assertEq(resolver.text(TEST_NODE, "displayName"), "amber-fox-42");
        assertEq(resolver.text(TEST_NODE, "pfp"), "ipfs://Qm...");
    }

    function test_setText_emitsEvent() public {
        vm.prank(nodeOwner);
        vm.expectEmit(true, true, false, true);
        emit IkhaaliResolver.TextChanged(TEST_NODE, "pfp", "pfp", "ipfs://Qm...");
        resolver.setText(TEST_NODE, "pfp", "ipfs://Qm...");
    }

    function test_setText_revertsForStranger() public {
        vm.prank(stranger);
        vm.expectRevert(IkhaaliResolver.NotAuthorized.selector);
        resolver.setText(TEST_NODE, "pfp", "ipfs://Qm...");
    }

    // --- ERC-165 --- //

    function test_supportsInterface_addr() public view {
        // addr(bytes32) selector = 0x3b3b57de
        assertTrue(resolver.supportsInterface(0x3b3b57de));
    }

    function test_supportsInterface_name() public view {
        // name(bytes32) selector = 0x691f3431
        assertTrue(resolver.supportsInterface(0x691f3431));
    }

    function test_supportsInterface_text() public view {
        // text(bytes32,string) selector = 0x59d1d43c
        assertTrue(resolver.supportsInterface(0x59d1d43c));
    }

    // --- Read defaults --- //

    function test_addr_defaultsToZero() public view {
        assertEq(resolver.addr(keccak256("nonexistent")), address(0));
    }

    function test_name_defaultsToEmpty() public view {
        assertEq(resolver.name(keccak256("nonexistent")), "");
    }

    function test_text_defaultsToEmpty() public view {
        assertEq(resolver.text(keccak256("nonexistent"), "key"), "");
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
forge test --match-contract khaaliResolverTest -v
```

Expected: compilation error — `khaaliResolver` does not exist yet.

- [ ] **Step 4: Implement khaaliResolver**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IkhaaliResolver} from "./IkhaaliResolver.sol";

interface IRNSRegistry {
    function owner(bytes32 node) external view returns (address);
}

contract khaaliResolver is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ERC165Upgradeable,
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
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
        rnsRegistry = IRNSRegistry(_rnsRegistry);
    }

    // --- Write --- //

    function setAddr(bytes32 node, address addr) external {
        _checkAuthorized(node);
        _addresses[node] = addr;
        emit AddrChanged(node, addr);
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
        override(AccessControlUpgradeable, ERC165Upgradeable)
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
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
forge test --match-contract khaaliResolverTest -v
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/account/modules/rns/ test/khaaliResolver.t.sol
git commit -m "feat: add khaaliResolver with forward/reverse resolution and text records"
```

---

## Task 2: IkhaaliAccount + khaaliAccount (Part A — Core + Initialization)

The account is the largest contract. We split it across two tasks: core structure + initialization first, then execution + modules.

**Files:**
- Create: `src/account/IkhaaliAccount.sol`
- Create: `src/account/khaaliAccount.sol`
- Create: `test/khaaliAccount.t.sol`

- [ ] **Step 1: Write IkhaaliAccount interface**

Full interface as specified in the design doc. Key points:

- **Define `PackedUserOperation` struct directly in the interface** (no external import available). Fields: `sender`, `nonce`, `initCode`, `callData`, `accountGasLimits`, `preVerificationGas`, `gasFees`, `paymasterAndData`, `signature` — matching ERC-4337 v0.7.
- `validateUserOp` and `execute` are `payable`
- Events: `ModuleInstalled`, `ModuleUninstalled`

- [ ] **Step 2: Write Part A tests — initialization and roles**

Add to `test/khaaliAccount.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliAccount} from "../src/account/khaaliAccount.sol";
import {IkhaaliAccount} from "../src/account/IkhaaliAccount.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

contract khaaliAccountTest is Test {

    khaaliAccount public accountImpl;
    khaaliAccount public account;
    MockEntryPoint public entryPoint;

    address owner;
    uint256 ownerKey;
    address manager = makeAddr("manager");
    address stranger = makeAddr("stranger");

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        entryPoint = new MockEntryPoint();

        accountImpl = new khaaliAccount(address(entryPoint));
        bytes memory initData = abi.encodeCall(
            khaaliAccount.initialize,
            (owner, manager)
        );
        account = khaaliAccount(payable(address(new ERC1967Proxy(address(accountImpl), initData))));
    }

    // --- Initialization --- //

    function test_init_ownerHasOwnerRole() public view {
        assertTrue(account.hasRole(account.OWNER_ROLE(), owner));
    }

    function test_init_ownerIsDefaultAdmin() public view {
        assertTrue(account.hasRole(account.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_init_managerHasManagerRole() public view {
        assertTrue(account.hasRole(account.MANAGER_ROLE(), manager));
    }

    function test_init_entryPointHasEntryPointRole() public view {
        assertTrue(account.hasRole(account.ENTRYPOINT_ROLE(), address(entryPoint)));
    }

    function test_init_cannotReinitialize() public {
        vm.expectRevert();
        account.initialize(owner, manager);
    }

    function test_init_entryPointReturnsCorrectAddress() public view {
        assertEq(account.entryPoint(), address(entryPoint));
    }

    function test_init_accountId() public view {
        assertEq(account.accountId(), "khaali.account.v1");
    }

    // --- UUPS --- //

    function test_upgrade_ownerCanUpgrade() public {
        khaaliAccount newImpl = new khaaliAccount(address(entryPoint));
        vm.prank(owner);
        account.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_strangerCannotUpgrade() public {
        khaaliAccount newImpl = new khaaliAccount(address(entryPoint));
        vm.prank(stranger);
        vm.expectRevert();
        account.upgradeToAndCall(address(newImpl), "");
    }

    // --- Receive ETH --- //

    function test_receiveEth() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool success,) = address(account).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(account).balance, 1 ether);
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
forge test --match-contract khaaliAccountTest -v
```

Expected: compilation error — `khaaliAccount` does not exist yet.

- [ ] **Step 4: Implement khaaliAccount — core + initialization**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";
import {Receiver} from "solady/accounts/Receiver.sol";
import {IkhaaliAccount} from "./IkhaaliAccount.sol";

contract khaaliAccount is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ERC165Upgradeable,
    Receiver,
    IkhaaliAccount
{
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant ENTRYPOINT_ROLE = keccak256("ENTRYPOINT_ROLE");
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");

    address private immutable _entryPoint;

    mapping(uint256 => EnumerableSet.AddressSet) private _modules;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address entryPoint_) {
        _entryPoint = entryPoint_;
        _disableInitializers();
    }

    function initialize(address owner, address manager) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        // OWNER_ROLE = DEFAULT_ADMIN_ROLE (admin of all roles)
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(OWNER_ROLE, owner);
        _grantRole(MANAGER_ROLE, manager);
        _grantRole(ENTRYPOINT_ROLE, _entryPoint);
    }

    function entryPoint() external view returns (address) {
        return _entryPoint;
    }

    function accountId() external pure returns (string memory) {
        return "khaali.account.v1";
    }

    // --- Stub functions (implemented in Task 3) --- //

    function validateUserOp(PackedUserOperation calldata, bytes32, uint256) external payable returns (uint256) {
        revert("not yet implemented");
    }

    function execute(bytes32, bytes calldata) external payable {
        revert("not yet implemented");
    }

    function executeFromExecutor(bytes32, bytes calldata) external returns (bytes[] memory) {
        revert("not yet implemented");
    }

    function installModule(uint256, address, bytes calldata) external {
        revert("not yet implemented");
    }

    function uninstallModule(uint256, address, bytes calldata) external {
        revert("not yet implemented");
    }

    function isModuleInstalled(uint256, address, bytes calldata) external view returns (bool) {
        return false;
    }

    function supportsExecutionMode(bytes32) external pure returns (bool) {
        return false;
    }

    function supportsModule(uint256) external pure returns (bool) {
        return false;
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }

    // --- ERC-165 --- //

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC165Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // --- UUPS --- //

    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    // --- Receiver fallback override --- //
    // Solady Receiver provides receive() and fallback() for ETH/ERC721/ERC1155.
    // Override fallback to check for installed fallback handler modules (type 3).
    // Full implementation in Task 3.
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
forge test --match-contract khaaliAccountTest -v
```

Expected: all Part A tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/account/IkhaaliAccount.sol src/account/khaaliAccount.sol test/khaaliAccount.t.sol
git commit -m "feat: add khaaliAccount core — initialization, roles, UUPS, stubs"
```

---

## Task 3: khaaliAccount (Part B — Execution, Modules, Signatures)

Fill in the stub functions: execute, executeFromExecutor, module management, validateUserOp, isValidSignature, fallback handler routing.

**Files:**
- Modify: `src/account/khaaliAccount.sol`
- Modify: `test/khaaliAccount.t.sol`

- [ ] **Step 1: Write Part B tests — execution**

Add to `khaaliAccountTest`:

Note: Solady's LibERC7579 provides `decodeSingle`/`decodeBatch` for decoding and `encodeMode` for mode encoding, but does NOT provide `encodeSingle`/`encodeBatch`. Execution data must be manually encoded:
- Single: `abi.encodePacked(address target, uint256 value, bytes data)`
- Batch: `abi.encode(Call[])` where `Call` is `(address target, uint256 value, bytes data)`

```solidity
// --- Execute (single) --- //

function test_execute_ownerCanExecuteSingle() public {
    vm.deal(address(account), 1 ether);
    // ERC-7579 single execution encoding: target (20 bytes) || value (32 bytes) || data
    bytes memory execData = abi.encodePacked(stranger, uint256(1 ether), bytes(""));
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    vm.prank(owner);
    account.execute(mode, execData);
    assertEq(stranger.balance, 1 ether);
}

function test_execute_strangerReverts() public {
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    vm.prank(stranger);
    vm.expectRevert();
    account.execute(mode, abi.encodePacked(stranger, uint256(0), bytes("")));
}

function test_executeFromExecutor_strangerReverts() public {
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    vm.prank(stranger);
    vm.expectRevert();
    account.executeFromExecutor(mode, abi.encodePacked(stranger, uint256(0), bytes("")));
}

// --- Execute (batch) --- //

function test_execute_ownerCanExecuteBatch() public {
    vm.deal(address(account), 2 ether);
    address target1 = makeAddr("target1");
    address target2 = makeAddr("target2");

    // ERC-7579 batch encoding: abi.encode of Call[] array
    // Each Call is (address target, uint256 value, bytes data)
    bytes[] memory calls = new bytes[](2);
    calls[0] = abi.encode(target1, uint256(1 ether), bytes(""));
    calls[1] = abi.encode(target2, uint256(1 ether), bytes(""));
    bytes memory execData = abi.encode(calls);

    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    vm.prank(owner);
    account.execute(mode, execData);
    assertEq(target1.balance, 1 ether);
    assertEq(target2.balance, 1 ether);
}

// --- supportsExecutionMode --- //

function test_supportsExecutionMode_single() public view {
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    assertTrue(account.supportsExecutionMode(mode));
}

function test_supportsExecutionMode_batch() public view {
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    assertTrue(account.supportsExecutionMode(mode));
}
```

- [ ] **Step 2: Write Part B tests — module management**

```solidity
// --- Module Management --- //

function test_installModule_executor() public {
    address mockModule = makeAddr("mockModule");
    vm.prank(owner);
    account.installModule(2, mockModule, "");
    assertTrue(account.isModuleInstalled(2, mockModule, ""));
    assertTrue(account.hasRole(account.MODULE_ROLE(), mockModule));
}

function test_installModule_managerCanInstall() public {
    address mockModule = makeAddr("mockModule");
    vm.prank(manager);
    account.installModule(2, mockModule, "");
    assertTrue(account.isModuleInstalled(2, mockModule, ""));
}

function test_uninstallModule_executor() public {
    address mockModule = makeAddr("mockModule");
    vm.prank(owner);
    account.installModule(2, mockModule, "");
    vm.prank(owner);
    account.uninstallModule(2, mockModule, "");
    assertFalse(account.isModuleInstalled(2, mockModule, ""));
    assertFalse(account.hasRole(account.MODULE_ROLE(), mockModule));
}

function test_installModule_strangerReverts() public {
    vm.prank(stranger);
    vm.expectRevert();
    account.installModule(2, makeAddr("mod"), "");
}

function test_supportsModule_types() public view {
    assertTrue(account.supportsModule(1));  // validator
    assertTrue(account.supportsModule(2));  // executor
    assertTrue(account.supportsModule(3));  // fallback handler
    assertFalse(account.supportsModule(4)); // hooks not supported
}
```

- [ ] **Step 3: Write Part B tests — validateUserOp (ERC-4337)**

```solidity
// --- ERC-4337 validateUserOp --- //

function test_validateUserOp_validOwnerSig() public {
    // Build a minimal PackedUserOperation
    IkhaaliAccount.PackedUserOperation memory userOp;
    userOp.sender = address(account);
    userOp.nonce = 0;
    bytes32 userOpHash = keccak256("test user op");

    // Sign the userOpHash with owner's key
    bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedHash);
    userOp.signature = abi.encodePacked(r, s, v);

    // EntryPoint calls validateUserOp
    vm.deal(address(account), 1 ether);
    vm.prank(address(entryPoint));
    uint256 result = account.validateUserOp(userOp, userOpHash, 0);
    assertEq(result, 0); // SIG_VALIDATION_SUCCESS
}

function test_validateUserOp_invalidSigReturns1() public {
    IkhaaliAccount.PackedUserOperation memory userOp;
    userOp.sender = address(account);
    bytes32 userOpHash = keccak256("test user op");

    (, uint256 strangerKey2) = makeAddrAndKey("stranger2");
    bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerKey2, ethSignedHash);
    userOp.signature = abi.encodePacked(r, s, v);

    vm.prank(address(entryPoint));
    uint256 result = account.validateUserOp(userOp, userOpHash, 0);
    assertEq(result, 1); // SIG_VALIDATION_FAILED
}

function test_validateUserOp_strangerReverts() public {
    IkhaaliAccount.PackedUserOperation memory userOp;
    bytes32 userOpHash = keccak256("test");
    vm.prank(stranger);
    vm.expectRevert();
    account.validateUserOp(userOp, userOpHash, 0);
}
```

- [ ] **Step 4: Write Part B tests — ERC-1271 signature validation**

```solidity
// --- ERC-1271 --- //

function test_isValidSignature_validOwnerSig() public view {
    bytes32 hash = keccak256("test message");
    bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedHash);
    bytes memory signature = abi.encodePacked(r, s, v);
    assertEq(account.isValidSignature(hash, signature), bytes4(0x1626ba7e));
}

function test_isValidSignature_invalidSig() public view {
    bytes32 hash = keccak256("test message");
    (, uint256 strangerKey) = makeAddrAndKey("stranger2");
    bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerKey, ethSignedHash);
    bytes memory signature = abi.encodePacked(r, s, v);
    assertEq(account.isValidSignature(hash, signature), bytes4(0xffffffff));
}
```

- [ ] **Step 5: Write Part B tests — ERC-165 interface reporting**

```solidity
// --- ERC-165 --- //

function test_supportsInterface_erc165() public view {
    assertTrue(account.supportsInterface(0x01ffc9a7)); // ERC-165
}

function test_supportsInterface_accessControl() public view {
    assertTrue(account.supportsInterface(0x7965db0b)); // IAccessControl
}

function test_supportsInterface_erc1271() public view {
    assertTrue(account.supportsInterface(0x1626ba7e)); // isValidSignature(bytes32,bytes)
}
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
forge test --match-contract khaaliAccountTest -v
```

Expected: new tests fail (stubs revert or return wrong values).

- [ ] **Step 7: Implement execute, executeFromExecutor**

Replace the stubs in `khaaliAccount.sol` with real implementations. Key logic:

- `execute`: require `OWNER_ROLE` or `ENTRYPOINT_ROLE`. Decode mode via `LibERC7579.getCallType()`. For `CALLTYPE_SINGLE`, decode target/value/data via `LibERC7579.decodeSingle()` and call. For `CALLTYPE_BATCH`, decode via `LibERC7579.decodeBatch()` and loop.
- `executeFromExecutor`: require `MODULE_ROLE`. Same decode/call logic, returns `bytes[]` of results.

- [ ] **Step 6: Implement module management**

Replace stubs:

- `installModule`: require `OWNER_ROLE` or `MANAGER_ROLE`. Add to `_modules[moduleTypeId]`. If executor (type 2), grant `MODULE_ROLE`. Call `onInstall(initData)` on the module if initData is non-empty.
- `uninstallModule`: same role check. Remove from `_modules`. If executor, revoke `MODULE_ROLE`. Call `onUninstall(deInitData)`.
- `isModuleInstalled`: return `_modules[moduleTypeId].contains(module)`.
- `supportsModule`: return `moduleTypeId >= 1 && moduleTypeId <= 3`.
- `supportsExecutionMode`: check callType is `CALLTYPE_SINGLE` or `CALLTYPE_BATCH`.

- [ ] **Step 9: Implement isValidSignature (ERC-1271)**

Replace stub. Recover signer from `toEthSignedMessageHash(hash)` + signature via `ECDSA.recover`. Check if recovered address `hasRole(OWNER_ROLE)`. Return `0x1626ba7e` on success, `0xffffffff` on failure.

- [ ] **Step 10: Implement validateUserOp (ERC-4337)**

Require `ENTRYPOINT_ROLE`. Recover signer from `userOpHash` + `userOp.signature` via ECDSA. If valid owner, pay `missingAccountFunds` to `msg.sender` (EntryPoint) and return 0. If invalid, return 1 (SIG_VALIDATION_FAILED).

- [ ] **Step 11: Implement supportsInterface (ERC-165)**

Override `supportsInterface` to include ERC-1271 interface ID (`0x1626ba7e`) in addition to what `super.supportsInterface` already covers (ERC-165, IAccessControl).

- [ ] **Step 12: Implement fallback handler routing**

Override Solady Receiver's fallback. On unknown selector, check if any fallback handler module (type 3) is installed. If so, `call` the first one with the full calldata and the original `msg.sender` appended (ERC-2771 pattern). Otherwise, fall through to Receiver default.

- [ ] **Step 13: Run all tests**

```bash
forge test --match-contract khaaliAccountTest -v
```

Expected: all tests pass.

- [ ] **Step 14: Commit**

```bash
git add src/account/khaaliAccount.sol test/khaaliAccount.t.sol
git commit -m "feat: khaaliAccount execution, modules, ERC-1271, ERC-4337 validation"
```

---

## Task 4: IRNSNameModuleV1 + RNSNameModuleV1

**Files:**
- Create: `src/account/modules/rns/IRNSNameModuleV1.sol`
- Create: `src/account/modules/rns/RNSNameModuleV1.sol`
- Create: `test/RNSNameModuleV1.t.sol`

- [ ] **Step 1: Write IRNSNameModuleV1 interface**

Since there is no importable `IERC7579Module` in Solady or OZ, define the ERC-7579 module lifecycle functions (`onInstall`, `onUninstall`, `isModuleType`) directly in the interface alongside the module-specific functions:
- Lifecycle: `onInstall(bytes)`, `onUninstall(bytes)`, `isModuleType(uint256) returns (bool)`
- Events: `NodeSet`, `NodeCleared`
- Functions: `updateAddress`, `updateTextRecord`, `updateName`, `nodeOf`

- [ ] **Step 2: Write module tests**

Tests need a deployed khaaliAccount with the module installed. The test setUp deploys an account proxy, a resolver proxy, and the module. Then installs the module on the account.

Key tests:
- `test_onInstall_storesNode` — install stores the subnode for the account
- `test_onUninstall_clearsNode` — uninstall deletes the mapping
- `test_isModuleType_executor` — returns true for type 2
- `test_nodeOf_returnsStoredNode` — returns the correct subnode
- `test_updateTextRecord_updatesResolver` — full round-trip: account calls module, module calls back through account, resolver record updated
- `test_updateAddress_updatesResolver` — same pattern for address records
- `test_updateName_updatesResolver` — same pattern for name records

The update tests are the most important — they verify the executor callback pattern works end-to-end:

```solidity
function test_updateTextRecord_updatesResolver() public {
    // account.execute -> module.updateTextRecord -> account.executeFromExecutor -> resolver.setText
    bytes memory moduleCall = abi.encodeCall(
        RNSNameModuleV1.updateTextRecord,
        (address(resolver), "pfp", "ipfs://Qm...")
    );
    bytes memory execData = abi.encodePacked(address(module), uint256(0), moduleCall);
    bytes32 mode = LibERC7579.encodeMode(
        LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
    );
    vm.prank(owner);
    account.execute(mode, execData);
    assertEq(resolver.text(testSubnode, "pfp"), "ipfs://Qm...");
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
forge test --match-contract RNSNameModuleV1Test -v
```

Expected: compilation error.

- [ ] **Step 4: Implement RNSNameModuleV1**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRNSNameModuleV1} from "./IRNSNameModuleV1.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";

interface IERC7579Account {
    function executeFromExecutor(bytes32 mode, bytes calldata executionData) external returns (bytes[] memory);
}

interface IResolver {
    function setAddr(bytes32 node, address addr) external;
    function setName(bytes32 node, string calldata name) external;
    function setText(bytes32 node, string calldata key, string calldata value) external;
}

contract RNSNameModuleV1 is IRNSNameModuleV1 {

    mapping(address => bytes32) private _nodes;

    function onInstall(bytes calldata data) external {
        bytes32 node = abi.decode(data, (bytes32));
        _nodes[msg.sender] = node;
        emit NodeSet(msg.sender, node);
    }

    function onUninstall(bytes calldata) external {
        delete _nodes[msg.sender];
        emit NodeCleared(msg.sender);
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == 2;
    }

    function nodeOf(address account) external view returns (bytes32) {
        return _nodes[account];
    }

    function updateAddress(address resolver, address newAddr) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "not installed");
        bytes memory callData = abi.encodeCall(IResolver.setAddr, (node, newAddr));
        _executeViaAccount(msg.sender, resolver, callData);
    }

    function updateTextRecord(address resolver, string calldata key, string calldata value) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "not installed");
        bytes memory callData = abi.encodeCall(IResolver.setText, (node, key, value));
        _executeViaAccount(msg.sender, resolver, callData);
    }

    function updateName(address resolver, string calldata newName) external {
        bytes32 node = _nodes[msg.sender];
        require(node != bytes32(0), "not installed");
        bytes memory callData = abi.encodeCall(IResolver.setName, (node, newName));
        _executeViaAccount(msg.sender, resolver, callData);
    }

    function _executeViaAccount(address account, address target, bytes memory callData) internal {
        bytes memory execData = abi.encodePacked(target, uint256(0), callData);
        bytes32 mode = LibERC7579.encodeMode(
            LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
        );
        IERC7579Account(account).executeFromExecutor(mode, execData);
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
forge test --match-contract RNSNameModuleV1Test -v
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/account/modules/rns/IRNSNameModuleV1.sol src/account/modules/rns/RNSNameModuleV1.sol test/RNSNameModuleV1.t.sol
git commit -m "feat: add RNSNameModuleV1 — ERC-7579 executor for RNS record management"
```

---

## Task 5: IkhaaliAccountFactory + khaaliAccountFactory

**Files:**
- Create: `src/account/IkhaaliAccountFactory.sol`
- Create: `src/account/khaaliAccountFactory.sol`
- Create: `test/khaaliAccountFactory.t.sol`

- [ ] **Step 1: Write IkhaaliAccountFactory interface**

As specified in the design doc. Includes:
- Event: `AccountCreated`
- Error: `NameCollision`
- Functions: `createAccount`, `getAddress`, `currentMilestone`, `userCount`, `initialize`

- [ ] **Step 2: Write factory tests**

The factory test needs the full stack: mock RNS registry, resolver, account impl, module, khaaliNames (with dictionaries). The setUp mirrors the existing test pattern for deploying dictionaries from text files.

Key tests:
- `test_init_adminRole` — admin has ADMIN_ROLE
- `test_init_configAddresses` — all config addresses stored correctly
- `test_currentMilestone_initial` — returns ANIMAL_30 when userCount is 0
- `test_currentMilestone_progression` — transitions at 10k, 100k, 1M thresholds
- `test_createAccount_deploysAccount` — returned address has code
- `test_createAccount_ownerSet` — owner has OWNER_ROLE on the account
- `test_createAccount_factoryHasManagerRole` — factory has MANAGER_ROLE
- `test_createAccount_moduleInstalled` — RNS module is installed on the account
- `test_createAccount_subnameRegistered` — subnode owner is the account in RNS registry
- `test_createAccount_resolverRecordsSet` — forward/reverse/text records set on resolver
- `test_createAccount_incrementsUserCount` — userCount goes from 0 to 1
- `test_createAccount_emitsEvent` — AccountCreated event emitted
- `test_getAddress_matchesActual` — predicted address matches deployed address

- [ ] **Step 3: Run tests to verify they fail**

```bash
forge test --match-contract khaaliAccountFactoryTest -v
```

Expected: compilation error.

- [ ] **Step 4: Implement khaaliAccountFactory**

Key implementation details:

- UUPS upgradeable, AccessControl with ADMIN_ROLE = DEFAULT_ADMIN_ROLE
- `initialize` stores all config addresses, grants ADMIN_ROLE
- `createAccount`:
  1. `userCount++`
  2. Salt = `keccak256(abi.encodePacked(owner, userCount))`
  3. Deploy proxy: `new ERC1967Proxy{salt: salt}(accountImplementation, initData)` where `initData = abi.encodeCall(khaaliAccount.initialize, (owner, address(this)))`
  4. Call `khaaliNames.getRandomName(account, currentMilestone())`
  5. Register subname on RNS: `setSubnodeOwner`, `setResolver`, then resolver writes
  6. Transfer subname ownership to account
  7. Install RNS module on account: `account.installModule(2, rnsModule, abi.encode(subnode))`
  8. Emit `AccountCreated`
- `getAddress`: compute CREATE2 address from salt + proxy initCodeHash
- `currentMilestone`: threshold checks against `userCount`

The reverse node computation helper:

```solidity
function _reverseNode(address addr) internal pure returns (bytes32) {
    // ADDR_REVERSE_NODE = namehash("addr.reverse")
    bytes32 ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
    return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, keccak256(bytes(_addressToHexString(addr)))));
}

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
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
forge test --match-contract khaaliAccountFactoryTest -v
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/account/IkhaaliAccountFactory.sol src/account/khaaliAccountFactory.sol test/khaaliAccountFactory.t.sol
git commit -m "feat: add khaaliAccountFactory — account deployment, naming, RNS registration"
```

---

## Task 6: Integration Test

End-to-end test of the full account creation flow and subsequent RNS record updates via the module.

**Files:**
- Create: `test/Integration.t.sol`

- [ ] **Step 1: Write integration test**

Full-stack test that:
1. Deploys all infrastructure (dictionaries, khaaliNames, mock RNS registry, resolver, account impl, module, factory)
2. Transfers RNS parent domain ownership to factory
3. Calls `factory.createAccount(alice)` and verifies:
   - Account exists at deterministic address
   - Alice has OWNER_ROLE
   - Factory has MANAGER_ROLE
   - RNS module is installed
   - Forward resolution works: `resolver.addr(subnode) == account`
   - Reverse resolution works: `resolver.name(reverseNode) == generatedName`
   - Text record set: `resolver.text(subnode, "displayName") == generatedName`
   - Account owns the subnode in RNS registry
4. Alice uses the module to update her pfp:
   - Account calls `module.updateTextRecord(resolver, "pfp", "ipfs://...")`
   - Verify `resolver.text(subnode, "pfp") == "ipfs://..."`
5. Creates a second account and verifies userCount incremented
6. Verifies milestone stays at ANIMAL_30 (only 2 users)

- [ ] **Step 2: Run the integration test**

```bash
forge test --match-contract IntegrationTest -v
```

Expected: all tests pass.

- [ ] **Step 3: Run full test suite**

```bash
forge test -v
```

Expected: all tests pass (existing khaaliNamesV1 tests + all new tests).

- [ ] **Step 4: Commit**

```bash
git add test/Integration.t.sol
git commit -m "test: add end-to-end integration test for account creation flow"
```

---

## Task 7: Cleanup + Gas Report

**Files:**
- Modify: `foundry.toml` (if fs_permissions need updates)
- Modify: `remappings.txt` (verify final state)
- Modify: `README.md` (update with account system section — only if user requests)

- [ ] **Step 1: Run full test suite one final time**

```bash
forge test -v
```

Expected: all tests pass.

- [ ] **Step 2: Generate gas report**

```bash
forge test --gas-report > gas-report-account.txt
```

- [ ] **Step 3: Verify build in production profile**

```bash
FOUNDRY_PROFILE=production forge build
```

Expected: compiles with via_ir and optimizer_runs=2000.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: finalize account system — gas report, production build verified"
```
