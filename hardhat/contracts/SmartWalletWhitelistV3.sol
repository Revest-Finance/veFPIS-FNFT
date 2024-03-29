// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

interface SmartWalletChecker {
    function check(address) external view returns (bool);
}

/**
 * 
 * @author RobAnon, Ekkila
 */
contract SmartWalletWhitelistV3 is AccessControl  {
    
    mapping(address => bool) public wallets;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    
    address public checker;
    address public future_checker;
    
    event ApproveWallet(address);
    event RevokeWallet(address);
    
    constructor(address _superAdmin) {
        _setupRole(DEFAULT_ADMIN_ROLE, _superAdmin);
    }
    
    function commitSetChecker(address _checker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        future_checker = _checker;
    }
    
    function applySetChecker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        checker = future_checker;
    }
    
    function approveWallet(address _wallet) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Error: Caller is not an admin!");
        wallets[_wallet] = true;
        
        emit ApproveWallet(_wallet);
    }

    function batchApproveWallets(address[] memory _wallets) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Error: Caller is not an admin!");
        for(uint i = 0; i < _wallets.length; i++) {
            wallets[_wallets[i]] = true;
            emit ApproveWallet(_wallets[i]);
        }
    }

    function revokeWallet(address _wallet) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Error: Caller is not an admin!");
        wallets[_wallet] = false;
        
        emit RevokeWallet(_wallet);
    }
    
    function check(address _wallet) external view returns (bool) {
        bool _check = wallets[_wallet];
        if (_check) {
            return _check;
        } else {
            if (checker != address(0)) {
                return SmartWalletChecker(checker).check(_wallet);
            }
        }
        return false;
    }
}