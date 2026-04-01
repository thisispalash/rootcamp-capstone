// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";

// Account
import {khaaliAccount} from "../src/account/khaaliAccount.sol";
import {IkhaaliAccount} from "../src/account/IkhaaliAccount.sol";
import {khaaliAccountFactory} from "../src/account/khaaliAccountFactory.sol";
import {IkhaaliAccountFactory} from "../src/account/IkhaaliAccountFactory.sol";

// Names + Dictionaries
import {khaaliNamesV1, Milestone} from "../src/khaaliNamesV1.sol";
import {IkhaaliDictionaryV1} from "../src/dictionary/IkhaaliDictionaryV1.sol";
import {ColorDictionaryV1} from "../src/dictionary/ColorDictionaryV1.sol";
import {AnimalDictionaryV1} from "../src/dictionary/AnimalDictionaryV1.sol";
import {AdjectiveDictionaryV1} from "../src/dictionary/AdjectiveDictionaryV1.sol";

// RNS
import {khaaliResolver} from "../src/account/modules/rns/khaaliResolver.sol";
import {RNSNameModuleV1} from "../src/account/modules/rns/RNSNameModuleV1.sol";
import {MockRNSRegistry} from "./mocks/MockRNSRegistry.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

/// @title IntegrationTest
/// @notice End-to-end integration test for the full account creation flow and
///         subsequent RNS record updates via the RNSNameModuleV1.
contract IntegrationTest is Test {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 constant WORD_LENGTH = 16;
    uint256 constant COLOR_COUNT = 50;
    uint256 constant ANIMAL_COUNT = 350;
    uint256 constant ADJECTIVE_COUNT = 1200;

    bytes32 constant PARENT_NODE = keccak256("test.rsk");

    // -------------------------------------------------------------------------
    // Contracts
    // -------------------------------------------------------------------------

    khaaliNamesV1 public names;
    MockRNSRegistry public registry;
    khaaliResolver public resolver;
    MockEntryPoint public entryPoint;
    khaaliAccount public accountImpl;
    RNSNameModuleV1 public module;
    khaaliAccountFactory public factory;

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // -------------------------------------------------------------------------
    // setUp — deploy the full stack
    // -------------------------------------------------------------------------

    function setUp() public {
        // 1. Deploy dictionaries + khaaliNamesV1
        address colorPointer = SSTORE2.write(_packWords("data/colors.txt", COLOR_COUNT));
        IkhaaliDictionaryV1 colorDict = new ColorDictionaryV1(colorPointer);

        address animalPointer = SSTORE2.write(_packWords("data/animals.txt", ANIMAL_COUNT));
        IkhaaliDictionaryV1 animalDict = new AnimalDictionaryV1(animalPointer);

        address adjectivePointer = SSTORE2.write(_packWords("data/adjectives.txt", ADJECTIVE_COUNT));
        IkhaaliDictionaryV1 adjectiveDict = new AdjectiveDictionaryV1(adjectivePointer);

        names = new khaaliNamesV1(animalDict, colorDict, adjectiveDict);

        // 2. Deploy MockRNSRegistry
        registry = new MockRNSRegistry();

        // 3. Deploy khaaliResolver behind ERC1967 proxy
        khaaliResolver resolverImpl = new khaaliResolver();
        bytes memory resolverInitData = abi.encodeCall(
            khaaliResolver.initialize,
            (admin, admin, address(registry))
        );
        resolver = khaaliResolver(address(new ERC1967Proxy(address(resolverImpl), resolverInitData)));

        // 4. Deploy MockEntryPoint + khaaliAccount implementation
        entryPoint = new MockEntryPoint();
        accountImpl = new khaaliAccount(address(entryPoint));

        // 5. Deploy RNSNameModuleV1
        module = new RNSNameModuleV1();

        // 6. Deploy khaaliAccountFactory behind ERC1967 proxy
        khaaliAccountFactory factoryImpl = new khaaliAccountFactory();
        bytes memory factoryInitData = abi.encodeCall(
            khaaliAccountFactory.initialize,
            (
                admin,
                address(accountImpl),
                address(names),
                address(registry),
                address(resolver),
                PARENT_NODE,
                address(module)
            )
        );
        factory = khaaliAccountFactory(address(new ERC1967Proxy(address(factoryImpl), factoryInitData)));

        // 7. Transfer parentNode ownership to the factory in the mock registry
        registry.forceSetOwner(PARENT_NODE, address(factory));

        // 8. Grant OPERATOR_ROLE to the factory on the resolver so it can write records
        bytes32 operatorRole = resolver.OPERATOR_ROLE();
        vm.prank(admin);
        resolver.grantRole(operatorRole, address(factory));
    }

    // -------------------------------------------------------------------------
    // Test 1 — Account creation for Alice
    // -------------------------------------------------------------------------

    function test_createAccount_accountExistsWithCode() public {
        (address accountAddr,) = factory.createAccount(alice);
        assertTrue(accountAddr != address(0), "account address should be non-zero");
        assertTrue(accountAddr.code.length > 0, "account should have code");
    }

    function test_createAccount_aliceHasOwnerRole() public {
        (address accountAddr,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(accountAddr));
        assertTrue(acct.hasRole(acct.OWNER_ROLE(), alice), "alice should have OWNER_ROLE");
    }

    function test_createAccount_factoryHasManagerRole() public {
        (address accountAddr,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(accountAddr));
        assertTrue(acct.hasRole(acct.MANAGER_ROLE(), address(factory)), "factory should have MANAGER_ROLE");
    }

    function test_createAccount_rnsModuleInstalled() public {
        (address accountAddr,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(accountAddr));
        assertTrue(
            acct.isModuleInstalled(2, address(module), ""),
            "RNS module should be installed as executor (type 2)"
        );
    }

    function test_createAccount_forwardResolution() public {
        (address accountAddr, string memory accountName) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(accountName));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));
        assertEq(resolver.addr(subnode), accountAddr, "forward resolution: subnode should resolve to account");
    }

    function test_createAccount_displayNameTextRecord() public {
        (, string memory accountName) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(accountName));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));
        string memory displayName = resolver.text(subnode, "displayName");
        assertTrue(bytes(displayName).length > 0, "displayName text record should be non-empty");
    }

    function test_createAccount_accountOwnsSubnode() public {
        (address accountAddr, string memory accountName) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(accountName));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));
        assertEq(registry.owner(subnode), accountAddr, "account should own its subnode in the RNS registry");
    }

    // -------------------------------------------------------------------------
    // Test 2 — Alice uses the RNS module to update her pfp
    // -------------------------------------------------------------------------

    function test_moduleUsage_aliceUpdatesPfp() public {
        (address accountAddr, string memory accountName) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(accountName));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));

        // Alice calls account.execute → module.updateTextRecord → resolver.setText
        bytes memory moduleCall = abi.encodeCall(
            RNSNameModuleV1.updateTextRecord,
            (address(resolver), "pfp", "ipfs://QmTest")
        );
        bytes memory execData = abi.encodePacked(address(module), uint256(0), moduleCall);
        bytes32 mode = LibERC7579.encodeMode(
            LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
        );

        vm.prank(alice);
        khaaliAccount(payable(accountAddr)).execute(mode, execData);

        assertEq(resolver.text(subnode, "pfp"), "ipfs://QmTest", "pfp text record should be updated");
    }

    // -------------------------------------------------------------------------
    // Test 3 — Second account for Bob, userCount = 2
    // -------------------------------------------------------------------------

    function test_twoAccounts_userCountIsTwo() public {
        factory.createAccount(alice);
        factory.createAccount(bob);
        assertEq(factory.userCount(), 2, "userCount should be 2 after two accounts");
    }

    // -------------------------------------------------------------------------
    // Test 4 — Milestone stays at ANIMAL_30 with only 2 users
    // -------------------------------------------------------------------------

    function test_milestone_staysAtAnimal30() public {
        factory.createAccount(alice);
        factory.createAccount(bob);
        assertEq(
            uint8(factory.currentMilestone()),
            uint8(Milestone.ANIMAL_30),
            "milestone should remain ANIMAL_30 with only 2 users"
        );
    }

    // -------------------------------------------------------------------------
    // Helpers (copied from khaaliNamesV1.t.sol)
    // -------------------------------------------------------------------------

    function _packWords(string memory filePath, uint256 count)
        internal
        view
        returns (bytes memory)
    {
        string memory fileContent = vm.readFile(filePath);
        bytes memory raw = bytes(fileContent);
        bytes memory packed = new bytes(count * WORD_LENGTH);

        uint256 start = 0;
        uint256 index = 0;

        for (uint256 i = 0; i <= raw.length; i++) {
            if (i == raw.length || raw[i] == 0x0A) { // line feed
                uint256 len = i - start;
                // Strip trailing CR for CRLF compatibility
                if (len > 0 && raw[start + len - 1] == 0x0D) len--;
                if (len > 0) {
                    require(len <= WORD_LENGTH, "Word too long for bytes16");
                    for (uint256 j = 0; j < len; j++) {
                        packed[index * WORD_LENGTH + j] = raw[start + j];
                    }
                    index++;
                }
                start = i + 1;
            }
        }

        require(index == count, "Expected more words than found");
        return packed;
    }
}
