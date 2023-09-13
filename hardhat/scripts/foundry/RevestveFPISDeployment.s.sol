pragma solidity <=0.8.19;

import {Script} from "forge-std/Script.sol";

import {RevestVeFPIS} from "contracts/RevestVeFPIS.sol";
import {SmartWalletWhitelistV2} from "contracts/SmartWalletWhitelistV2.sol";

import {console2 as console} from "forge-std/console2.sol";

interface ICREATE3Factory {
    /// @notice Deploys a contract using CREATE3
    /// @dev The provided salt is hashed together with msg.sender to generate the final salt
    /// @param salt The deployer-specific salt for determining the deployed contract's address
    /// @param creationCode The creation code of the contract to deploy
    /// @return deployed The address of the deployed contract
    function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed);
}

contract RevestVeFPISDeployment is Script {
    //Deployed Omni-Chain
    ICREATE3Factory factory = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    address revestRegistry = 0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78;
    address veFPIS = 0x574C154C83432B0A45BA3ad2429C3fA242eD7359;
    address distritbutor = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6;

    address adminWallet = 0x0eCBb61d0698AEFeaDC26BdC2d328Bc170D2CDf2; // my address deployer

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployer);

        address revestVeFPIS = factory.deploy(keccak256(abi.encode("RevestVeFPIS")), abi.encodePacked(type(RevestVeFPIS).creationCode, abi.encode(revestRegistry, veFPIS, distritbutor, adminWallet)));
        address smartWalletChecker = factory.deploy(keccak256(abi.encode("RevestVeFPIS")), abi.encodePacked(type(RevestVeFPIS).creationCode, abi.encode(adminWallet)));

        SmartWalletWhitelistV2(smartWalletChecker).changeAdmin(revestVeFPIS, true);
        
        vm.stopBroadcast();
        console.log("---DEPLOYMENT SUCCESSFUL---");


    }
}
