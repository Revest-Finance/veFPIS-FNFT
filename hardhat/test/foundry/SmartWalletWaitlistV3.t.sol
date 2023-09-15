// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/SmartWalletWhitelistV2.sol";


contract SmartWalletWaitlistV3 is Test {
    address superAdmin = makeAddr("superAdmin");

    address admin1 = makeAddr("admin1");
    address admin2 = makeAddr("admin2");
    address admin3 = makeAddr("admin3");

    address wallet1 = makeAddr("wallet1");
    address wallet2 = makeAddr("wallet2");
    address wallet3 = makeAddr("wallet3");

    function setUp() public {
        smartWalletChecker = new SmartWalletWhitelistV2(superAdmin, admin1);

        // label address
        vm.label(superAdmin, "superAdmin");
        vm.label(admin1, "admin1");
        vm.label(admin2, "admin2");
        vm.label(admin3, "admin3");
        vm.label(wallet1, "wallet1");
        vm.label(wallet2, "wallet2");
        vm.label(wallet3, "wallet3");

    }

    /**
     * 
     */
    function testConstructor(uint amount) public {
    
    }
}
