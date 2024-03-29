// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity >=0.8.0;

import "./IRegistryProvider.sol";
import '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/**
 * @title Provider interface for Revest FNFTs
 */
interface IVotingEscrow {

    struct Point {
        int128 bias;
        int128 slope;
        uint ts;
        uint blk;
    }

    struct LockedBalance {
        int128 amount;
        uint end;
    }

    function proxy_slash(address staker, uint amount) external;

    function transfer_from_app(address _staker, address _transferTo, int128 _transfer_amt) external;

     function transfer_to_app(address _staker, address _transferTo, int128 _transfer_amt) external;

    function create_lock(uint _value, uint _unlock_time) external;

    function increase_amount(uint _value) external;

    function increase_unlock_time(uint _unlock_time) external;

    function withdraw() external;

    function commit_smart_wallet_checker(address addr) external;

    function apply_smart_wallet_checker() external;

    function smart_wallet_checker() external view returns (address walletCheck);

    function token() external view returns (address tok);

    function locked(address _addr) external view returns (int128 amount, uint256 end);

    function locked__end(address _addr) external view returns (uint lockEnd);

    function balanceOf(address _addr) external view returns (uint balance);

    function user_point_epoch(address _addr) external view returns (uint epoch);

    function user_point_history(address _addr, uint index) external view returns (Point memory pt);

    function toggleTransferFromApp() external;

    function toggleTransferToApp() external;

    function toggleProxyAdds() external;

    function adminSetProxy(address proxy) external;

    function stakerSetProxy(address proxy) external;

}
