// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {khaaliAccount} from "../src/account/khaaliAccount.sol";
import {IkhaaliAccount} from "../src/account/IkhaaliAccount.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";
import {LibERC7579} from "solady/accounts/LibERC7579.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract khaaliAccountTest is Test {

    khaaliAccount public accountImpl;
    khaaliAccount public account;
    MockEntryPoint public entryPoint;

    address owner;
    uint256 ownerKey;
    address manager = makeAddr("manager");
    address stranger = makeAddr("stranger");

    /// @dev Helper struct for batch encoding (matches Solady's expected ABI layout).
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

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

    // =========================================================================
    // Part A — Initialization Tests
    // =========================================================================

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

    function test_receiveEth() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool success,) = address(account).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(account).balance, 1 ether);
    }

    // =========================================================================
    // Part B — Execution Tests
    // =========================================================================

    function test_execute_ownerCanExecuteSingle() public {
        vm.deal(address(account), 1 ether);
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

    function test_execute_ownerCanExecuteBatch() public {
        vm.deal(address(account), 2 ether);
        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");

        // Batch encoding: abi.encode of Call[] array (matches Solady's decodeBatch expectation)
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: target1, value: 1 ether, data: ""});
        calls[1] = Call({target: target2, value: 1 ether, data: ""});

        bytes32 mode = LibERC7579.encodeMode(
            LibERC7579.CALLTYPE_BATCH, LibERC7579.EXECTYPE_DEFAULT, bytes4(0), bytes22(0)
        );

        vm.prank(owner);
        account.execute(mode, abi.encode(calls));

        assertEq(target1.balance, 1 ether);
        assertEq(target2.balance, 1 ether);
    }

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

    // =========================================================================
    // Part B — Module Management Tests
    // =========================================================================

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
        assertTrue(account.supportsModule(1));
        assertTrue(account.supportsModule(2));
        assertTrue(account.supportsModule(3));
        assertFalse(account.supportsModule(4));
    }

    // =========================================================================
    // Part B — validateUserOp Tests
    // =========================================================================

    function test_validateUserOp_validOwnerSig() public {
        IkhaaliAccount.PackedUserOperation memory userOp;
        userOp.sender = address(account);
        userOp.nonce = 0;
        bytes32 userOpHash = keccak256("test user op");
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        vm.deal(address(account), 1 ether);
        vm.prank(address(entryPoint));
        uint256 result = account.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 0);
    }

    function test_validateUserOp_invalidSigReturns1() public {
        IkhaaliAccount.PackedUserOperation memory userOp;
        userOp.sender = address(account);
        bytes32 userOpHash = keccak256("test user op");
        (, uint256 strangerKey2) = makeAddrAndKey("stranger2");
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerKey2, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        vm.prank(address(entryPoint));
        uint256 result = account.validateUserOp(userOp, userOpHash, 0);
        assertEq(result, 1);
    }

    function test_validateUserOp_strangerReverts() public {
        IkhaaliAccount.PackedUserOperation memory userOp;
        bytes32 userOpHash = keccak256("test");
        vm.prank(stranger);
        vm.expectRevert();
        account.validateUserOp(userOp, userOpHash, 0);
    }

    // =========================================================================
    // Part B — ERC-1271 Tests
    // =========================================================================

    function test_isValidSignature_validOwnerSig() public {
        bytes32 hash = keccak256("test message");
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(hash, signature), bytes4(0x1626ba7e));
    }

    function test_isValidSignature_invalidSig() public {
        bytes32 hash = keccak256("test message");
        (, uint256 strangerKey2) = makeAddrAndKey("stranger2");
        bytes32 ethSignedHash = ECDSA.toEthSignedMessageHash(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerKey2, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(account.isValidSignature(hash, signature), bytes4(0xffffffff));
    }

    // =========================================================================
    // Part B — ERC-165 Tests
    // =========================================================================

    function test_supportsInterface_erc165() public view {
        assertTrue(account.supportsInterface(0x01ffc9a7));
    }

    function test_supportsInterface_accessControl() public view {
        assertTrue(account.supportsInterface(0x7965db0b));
    }

    function test_supportsInterface_erc1271() public view {
        assertTrue(account.supportsInterface(0x1626ba7e));
    }
}
