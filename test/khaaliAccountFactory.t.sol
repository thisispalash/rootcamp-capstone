// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

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
import {IkhaaliResolver} from "../src/account/modules/rns/IkhaaliResolver.sol";
import {RNSNameModuleV1} from "../src/account/modules/rns/RNSNameModuleV1.sol";
import {MockRNSRegistry} from "./mocks/MockRNSRegistry.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

contract khaaliAccountFactoryTest is Test {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 constant WORD_LENGTH = 16;
    uint256 constant COLOR_COUNT = 50;
    uint256 constant ANIMAL_COUNT = 350;
    uint256 constant ADJECTIVE_COUNT = 1200;

    bytes32 constant PARENT_NODE = keccak256("khaali.rsk");

    // -------------------------------------------------------------------------
    // Contracts
    // -------------------------------------------------------------------------

    khaaliNamesV1 public names;
    MockRNSRegistry public registry;
    khaaliResolver public resolver;
    MockEntryPoint public entryPoint;
    khaaliAccount public accountImpl;
    RNSNameModuleV1 public rnsModule;
    khaaliAccountFactory public factory;

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // -------------------------------------------------------------------------
    // setUp
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

        // 3. Deploy khaaliResolver behind proxy
        //    The factory needs OPERATOR_ROLE to write resolver records during createAccount.
        khaaliResolver resolverImpl = new khaaliResolver();
        // We'll grant OPERATOR_ROLE to the factory after it's deployed.
        // For now, grant to admin so we can add more operators later.
        bytes memory resolverInitData = abi.encodeCall(
            khaaliResolver.initialize,
            (admin, admin, address(registry))
        );
        resolver = khaaliResolver(address(new ERC1967Proxy(address(resolverImpl), resolverInitData)));

        // 4. Deploy MockEntryPoint + khaaliAccount implementation
        entryPoint = new MockEntryPoint();
        accountImpl = new khaaliAccount(address(entryPoint));

        // 5. Deploy RNSNameModuleV1
        rnsModule = new RNSNameModuleV1();

        // 6. Deploy khaaliAccountFactory behind proxy
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
                address(rnsModule)
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
    // Initialization Tests
    // -------------------------------------------------------------------------

    function test_init_adminRole() public view {
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_init_configAddresses() public view {
        assertEq(factory.accountImplementation(), address(accountImpl));
        assertEq(factory.khaaliNames(), address(names));
        assertEq(factory.rnsRegistry(), address(registry));
        assertEq(factory.resolver(), address(resolver));
        assertEq(factory.parentNode(), PARENT_NODE);
        assertEq(factory.rnsModule(), address(rnsModule));
    }

    // -------------------------------------------------------------------------
    // Milestone Tests
    // -------------------------------------------------------------------------

    function test_currentMilestone_initial() public view {
        assertEq(uint8(factory.currentMilestone()), uint8(Milestone.ANIMAL_30));
    }

    // -------------------------------------------------------------------------
    // createAccount Tests
    // -------------------------------------------------------------------------

    function test_createAccount_deploysAccount() public {
        (address account,) = factory.createAccount(alice);
        assertTrue(account.code.length > 0);
    }

    function test_createAccount_ownerSet() public {
        (address account,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(account));
        assertTrue(acct.hasRole(acct.OWNER_ROLE(), alice));
    }

    function test_createAccount_factoryHasManagerRole() public {
        (address account,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(account));
        assertTrue(acct.hasRole(acct.MANAGER_ROLE(), address(factory)));
    }

    function test_createAccount_moduleInstalled() public {
        (address account,) = factory.createAccount(alice);
        khaaliAccount acct = khaaliAccount(payable(account));
        assertTrue(acct.isModuleInstalled(2, address(rnsModule), ""));
    }

    function test_createAccount_subnameOwnedByAccount() public {
        (address account, string memory name) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(name));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));
        assertEq(registry.owner(subnode), account);
    }

    function test_createAccount_resolverRecordsSet() public {
        (address account, string memory name) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(name));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));
        // Forward resolution: subnode → address
        assertEq(resolver.addr(subnode), account);
    }

    function test_createAccount_incrementsUserCount() public {
        assertEq(factory.userCount(), 0);
        factory.createAccount(alice);
        assertEq(factory.userCount(), 1);
    }

    function test_createAccount_emitsEvent() public {
        // We can't predict the exact values for non-indexed params ahead of time,
        // so we create the account first to learn the name, then test a second account.
        // Alternatively, just check that the event is emitted with correct indexed params.
        vm.recordLogs();
        (address account, string memory name) = factory.createAccount(alice);
        bytes32 label = keccak256(bytes(name));
        bytes32 subnode = keccak256(abi.encodePacked(PARENT_NODE, label));

        // Verify using recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // Find the AccountCreated event
        bytes32 eventSig = keccak256("AccountCreated(address,address,string,bytes32)");
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSig) {
                assertEq(address(uint160(uint256(entries[i].topics[1]))), account);
                assertEq(address(uint160(uint256(entries[i].topics[2]))), alice);
                assertEq(entries[i].topics[3], subnode);
                found = true;
                break;
            }
        }
        assertTrue(found, "AccountCreated event not found");
    }

    // -------------------------------------------------------------------------
    // getAddress Tests
    // -------------------------------------------------------------------------

    function test_getAddress_matchesActual() public {
        // Predict address for alice at userCount=1 (will be incremented to 1 on first call)
        address predicted = factory.getAddress(alice, 1);
        (address actual,) = factory.createAccount(alice);
        assertEq(predicted, actual);
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
