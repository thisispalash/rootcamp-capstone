// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";

import {khaaliAccount} from "../src/account/khaaliAccount.sol";
import {khaaliResolver} from "../src/account/modules/rns/khaaliResolver.sol";
import {RNSNameModuleV1} from "../src/account/modules/rns/RNSNameModuleV1.sol";
import {IRNSNameModuleV1} from "../src/account/modules/rns/IRNSNameModuleV1.sol";
import {MockRNSRegistry} from "./mocks/MockRNSRegistry.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

contract RNSNameModuleV1Test is Test {

    // -------------------------------------------------------------------------
    // Contracts
    // -------------------------------------------------------------------------

    MockRNSRegistry public registry;

    khaaliResolver public resolverImpl;
    khaaliResolver public resolver;

    MockEntryPoint public entryPoint;
    khaaliAccount public accountImpl;
    khaaliAccount public account;

    RNSNameModuleV1 public module;

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address public owner = makeAddr("owner");
    address public manager = makeAddr("manager");
    address public admin = makeAddr("admin");

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 public constant TEST_NODE = keccak256("test.account.node");

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        // 1. Deploy MockRNSRegistry
        registry = new MockRNSRegistry();

        // 2. Deploy khaaliResolver behind ERC1967Proxy
        resolverImpl = new khaaliResolver();
        bytes memory resolverInitData = abi.encodeCall(
            khaaliResolver.initialize,
            (admin, admin, address(registry))
        );
        resolver = khaaliResolver(address(new ERC1967Proxy(address(resolverImpl), resolverInitData)));

        // 3. Deploy MockEntryPoint + khaaliAccount behind ERC1967Proxy
        entryPoint = new MockEntryPoint();
        accountImpl = new khaaliAccount(address(entryPoint));
        bytes memory accountInitData = abi.encodeCall(
            khaaliAccount.initialize,
            (owner, manager)
        );
        account = khaaliAccount(payable(address(new ERC1967Proxy(address(accountImpl), accountInitData))));

        // 4. Deploy RNSNameModuleV1
        module = new RNSNameModuleV1();

        // 5. Make account the owner of the test subnode in the registry
        registry.forceSetOwner(TEST_NODE, address(account));

        // 6. Install module on account (owner calls installModule with type=2)
        vm.prank(owner);
        account.installModule(2, address(module), abi.encode(TEST_NODE));
    }

    // -------------------------------------------------------------------------
    // onInstall / onUninstall
    // -------------------------------------------------------------------------

    function test_onInstall_storesNode() public view {
        assertEq(module.nodeOf(address(account)), TEST_NODE);
    }

    function test_onUninstall_clearsNode() public {
        vm.prank(owner);
        account.uninstallModule(2, address(module), abi.encode(bytes32(0)));
        assertEq(module.nodeOf(address(account)), bytes32(0));
    }

    // -------------------------------------------------------------------------
    // isModuleType
    // -------------------------------------------------------------------------

    function test_isModuleType_executor() public view {
        assertTrue(module.isModuleType(2));
        assertFalse(module.isModuleType(1));
        assertFalse(module.isModuleType(3));
        assertFalse(module.isModuleType(4));
    }

    // -------------------------------------------------------------------------
    // Update round-trips
    // -------------------------------------------------------------------------

    /// @dev Builds a single-call execution mode (same as used throughout the project).
    function _singleMode() internal pure returns (bytes32) {
        return LibERC7579.encodeMode(
            LibERC7579.CALLTYPE_SINGLE, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
        );
    }

    function test_updateTextRecord_updatesResolver() public {
        // owner → account.execute → module.updateTextRecord → account.executeFromExecutor → resolver.setText
        bytes memory innerCall = abi.encodeCall(
            RNSNameModuleV1.updateTextRecord,
            (address(resolver), "pfp", "ipfs://QmTest")
        );
        bytes memory execData = abi.encodePacked(address(module), uint256(0), innerCall);

        vm.prank(owner);
        account.execute(_singleMode(), execData);

        assertEq(resolver.text(TEST_NODE, "pfp"), "ipfs://QmTest");
    }

    function test_updateAddress_updatesResolver() public {
        address newAddr = makeAddr("newAddr");
        bytes memory innerCall = abi.encodeCall(
            RNSNameModuleV1.updateAddress,
            (address(resolver), newAddr)
        );
        bytes memory execData = abi.encodePacked(address(module), uint256(0), innerCall);

        vm.prank(owner);
        account.execute(_singleMode(), execData);

        assertEq(resolver.addr(TEST_NODE), newAddr);
    }

    function test_updateName_updatesResolver() public {
        bytes memory innerCall = abi.encodeCall(
            RNSNameModuleV1.updateName,
            (address(resolver), "amber-fox-42.rsk")
        );
        bytes memory execData = abi.encodePacked(address(module), uint256(0), innerCall);

        vm.prank(owner);
        account.execute(_singleMode(), execData);

        assertEq(resolver.name(TEST_NODE), "amber-fox-42.rsk");
    }
}
