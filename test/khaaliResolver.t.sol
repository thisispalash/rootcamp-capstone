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
        assertTrue(resolver.supportsInterface(0x3b3b57de));
    }

    function test_supportsInterface_name() public view {
        assertTrue(resolver.supportsInterface(0x691f3431));
    }

    function test_supportsInterface_text() public view {
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
