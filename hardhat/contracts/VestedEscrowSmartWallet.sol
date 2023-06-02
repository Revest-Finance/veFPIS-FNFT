// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IDistributor.sol";
import "./interfaces/IRewardsHandler.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


pragma solidity ^0.8.0;

/// @author RobAnon
contract VestedEscrowSmartWallet {

    using SafeERC20 for IERC20;

    uint private constant MAX_INT = 2 ** 256 - 1;

    address private immutable MASTER;

    address private immutable REWARD_TOKEN;

    address private immutable TOKEN;

    address private immutable VOTING_ESCROW;

    uint private constant feeNumerator = 10; // TODO: Make mutable

    uint private constant feeDenominator = 100;

    constructor(address _rewardToken, address _token, address _vE) {
        MASTER = msg.sender;
        REWARD_TOKEN = _rewardToken;
        TOKEN = _token;
        VOTING_ESCROW = _vE;
    }

    modifier onlyMaster() {
        require(msg.sender == MASTER, 'Unauthorized!');
        _;
    }

    function createLock(uint value, uint unlockTime) external onlyMaster {
        // Only callable from the parent contract, transfer tokens from user -> parent, parent -> VE
        // Single-use approval system
        if(IERC20(TOKEN).allowance(address(this), VOTING_ESCROW) != MAX_INT) {
            IERC20(TOKEN).approve(VOTING_ESCROW, MAX_INT);
        }
        // Create the lock
        IVotingEscrow(VOTING_ESCROW).create_lock(value, unlockTime);
        _cleanMemory();
    }

    function increaseAmount(uint value, address votingEscrow) external onlyMaster {
        IVotingEscrow(votingEscrow).increase_amount(value);
        _cleanMemory();
    }

    function increaseUnlockTime(uint unlockTime, address votingEscrow) external onlyMaster {
        IVotingEscrow(votingEscrow).increase_unlock_time(unlockTime);
        _cleanMemory();
    }

    function withdraw(address votingEscrow) external onlyMaster {
        address token = IVotingEscrow(votingEscrow).token();
        IVotingEscrow(votingEscrow).withdraw();
        uint bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(MASTER, bal);
        _cleanMemory();
    }

    function claimRewards(
        address distributor, 
        address caller, 
        address rewards
    ) external onlyMaster {
        IDistributor(distributor).getYield();
        uint bal = IERC20(REWARD_TOKEN).balanceOf(address(this));
        uint fee = bal * feeNumerator / feeDenominator;
        bal -= fee;
        IRewardsHandler(rewards).receiveFee(REWARD_TOKEN, fee);
        IERC20(REWARD_TOKEN).safeTransfer(caller, bal);
        _cleanMemory();
    }

    // Proxy function for ease of use and gas-savings
    function proxyApproveAll(address[] memory tokens, address spender) external onlyMaster {
        for(uint i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(spender, MAX_INT);
        }
    }

    /// Proxy function to send arbitrary messages. Useful for delegating votes and similar activities
    function proxyExecute(
        address destination,
        bytes memory data
    ) external payable onlyMaster returns (bytes memory dataOut) {
        (bool success, bytes memory dataTemp)= destination.call{value:msg.value}(data);
        require(success, 'Proxy call failed!');
        dataOut = dataTemp;
    }

    /// Credit to doublesharp for the brilliant gas-saving concept
    /// Self-destructing clone pattern
    function cleanMemory() external onlyMaster {
        _cleanMemory();
    }

    function _cleanMemory() internal {
        selfdestruct(payable(MASTER));
    }

}
