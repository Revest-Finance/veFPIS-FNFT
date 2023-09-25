// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/SmartWalletWhitelistV3.sol";

contract SmartWalletWaitlistV3 is Test {

    //List of addresses
    address superAdmin = makeAddr("superAdmin");

    address admin1 = makeAddr("admin1");
    address admin2 = makeAddr("admin2");
    address admin3 = makeAddr("admin3");

    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");
    address wallet3 = makeAddr("wallet3");

    address stranger = makeAddr("stranger");

    //Lists of role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant SUPER_ADMIN_ROLE = 0x00;

    //SmartWalletWhitelistV3
     SmartWalletWhitelistV3 smartWalletChecker;

    function setUp() public {
        smartWalletChecker = new SmartWalletWhitelistV3(superAdmin);

        // label address
        vm.label(superAdmin, "superAdmin");
        vm.label(admin1, "admin1");
        vm.label(admin2, "admin2");
        vm.label(admin3, "admin3");
        vm.label(wallet1, "wallet1");
        vm.label(wallet2, "wallet2");
        vm.label(wallet3, "wallet3");
        vm.label(stranger, "stranger");

        hoax(superAdmin, superAdmin);
        smartWalletChecker.grantRole(ADMIN_ROLE, admin1);
    }

    /**
     * 
     */
    function testInitialRoleAssignment() public {
        //test if superAdmin actually has the role
        bool superAdminSet  = smartWalletChecker.hasRole(SUPER_ADMIN_ROLE, superAdmin);
        assertEq(superAdminSet, true, "superAdmin role has not been assigned correctly!");

        //test if the first admin has the role
        bool adminSet = smartWalletChecker.hasRole(ADMIN_ROLE, admin1);
        assertEq(adminSet, true, "admin role has not been assigned correctly!");
    }

    /**
     * 
     */
    function testAddAmin() public {
        //test add wallet function from non-admin address
        hoax(admin2, admin2);
        vm.expectRevert("Error: Caller is not an admin!");
        smartWalletChecker.approveWallet(wallet1);

        //grant role Admin to admin2 
        hoax(superAdmin, superAdmin);
        smartWalletChecker.grantRole(ADMIN_ROLE, admin2);

        //test add wallet from admin address
        hoax(admin2, admin2);
        smartWalletChecker.approveWallet(wallet1);

        //check if wallet is approved or not
        bool isApproved = smartWalletChecker.check(wallet1);
        assertEq(isApproved, true, "Wallet has not been whitelisted!");
    }

    function testRevokeAdmin() public {
        //set-up
        hoax(superAdmin, superAdmin);
        smartWalletChecker.grantRole(ADMIN_ROLE, admin2);

        //test if current admin can add wallets
        hoax(admin1, admin1);
        smartWalletChecker.approveWallet(wallet1);
        
        bool isApproved = smartWalletChecker.check(wallet1);
        assertEq(isApproved, true, "Wallet has not been whitelisted!");

        //revoke admin as a stranger
        hoax(stranger, stranger);
        vm.expectRevert();
        smartWalletChecker.revokeRole(ADMIN_ROLE, admin1);

        //revoke admin as another admin
        hoax(admin2, admin2);
        vm.expectRevert();
        smartWalletChecker.revokeRole(ADMIN_ROLE, admin1);

        //revoke admin as a super admin
        hoax(superAdmin, superAdmin);
        smartWalletChecker.revokeRole(ADMIN_ROLE, admin1);

        //test if the removed admin can still approve wallet
        hoax(admin1, admin1);
        vm.expectRevert("Error: Caller is not an admin!");
        smartWalletChecker.approveWallet(wallet2);
    } 
}
