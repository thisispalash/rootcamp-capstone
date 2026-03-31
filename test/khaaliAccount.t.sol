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
}
