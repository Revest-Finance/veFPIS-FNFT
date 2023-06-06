// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/RevestVeFPIS.sol";
import "contracts/VestedEscrowSmartWallet.sol";
import "contracts/SmartWalletWhitelistV2.sol";
import "contracts/interfaces/IVotingEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


interface Revest {
    function withdrawFNFT(uint tokenUID, uint quantity) external;
    function depositAdditionalToFNFT(uint fnftId, uint amount,uint quantity) external returns (uint);
    function extendFNFTMaturity(uint fnftId,uint endTime ) external returns (uint);
    function modifyWhitelist(address contra, bool listed) external;

}

contract veFPISRevest is Test {
    address public Provider = 0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public VOTING_ESCROW = 0x574C154C83432B0A45BA3ad2429C3fA242eD7359; //TODO: change to veFPIS 
    adress public YIELD_DISTRIBUTOR = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6; //TODO: what is this ?

    address public veFPISAdmin = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
    address public revestOwner = 0x801e08919a483ceA4C345b5f8789E506e2624ccf;

    Revest revest = Revest(0x9f551F75DB1c301236496A2b4F7CeCb2d1B2b242);
    ERC20 FPIS = ERC20(0xc2544A32872A91F4A553b404C6950e89De901fdb);

    RevestVeFPIS revestVe;
    SmartWalletWhitelistV2 smartWalletChecker;
    IVotingEscrow veFPIS =  IVotingEscrow(VOTING_ESCROW);

    address admin = makeAddr("admin");
    address fpisWhale = 0x89623FBA59e54c9863346b4d27F0f86369Da11E5;

    uint fnftId;
    uint fnftId2;

    address smartWalletAddress;


    function setUp() public {
        revestVe  = new RevestveFPIS(Provider, VOTING_ESCROW, admin);
        smartWalletChecker = new SmartWalletWhitelistV2(admin);
        
        hoax(admin, admin);
        smartWalletChecker.changeAdmin(address(revestVe), true);

        vm.label(address(admin), "admin");
        vm.label(address(fpisWhale), "fpisWhale");
        vm.label(address(revest), "revest");
        vm.label(address(revestOwner), "revestOwner");
        vm.label(address(FPIS), "FPIS");

        hoax(revestOwner, revestOwner);
        revest.modifyWhitelist(address(revestVe), true);

        hoax(veFPISAdmin, veFPISAdmin);
        veFPIS.commit_smart_wallet_checker(address(smartWalletChecker));

        hoax(veFPISAdmin, veFPISAdmin);
        veFPIS.apply_smart_wallet_checker();
    }

    /**
     * This test case focus on if the user is able to mint the FNFT after deposit 1 token of FPIS into veFPIS 
     */
    function testMint() public {
        uint time = block.timestamp;
    
        //Outline the parameters that will govern the FNFT
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint fee = 1 wei;
        uint amount = 1.1e18; //FPIS 

        //Mint the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.lockTokens(expiration, amount);

        uint expectedValue = revestVe.getValue(fnftId);
        console.log("veFPIS balance should be around 2e18: ", expectedValue);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);
        console.log("SmartWallet add at address: ", smartWalletAddress);
        console.log("The minted FNFT has the ID: ", fnftId);
    }


    /**
     * This test case focus on if when the admin can receive the fee
     */
    function testReceiveFee() public {
        //Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint fee = 1 wei;
        uint amount = 1e18; //FPIS  

        //Balance of admin before the minting the lock
        console.log("FPIS balance of revest admin before minting: ", FPIS.balanceOf(address(admin)));

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.lockTokens(expiration, amount);

        //Value check
        console.log("FPIS balance of revest admin after minting: ", FPIS.balanceOf(address(admin)));
        assertEq(FPIS.balanceOf(address(admin)), 1e17);
    }

    /**
     * This test case focus on if user can deposit additional amount into the vault
     */
    function testDepositAdditional() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.lockTokens(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);
        console.log("SmartWallet add at address: ", smartWalletAddress);

        //Testing Phase
        console.log("Current veFPIS balance in Smart Wallet: ", revestVe.getValue(fnftId));

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Deposit additional fund for FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        revest.depositAdditionalToFNFT(fnftId, amount, 1);

        //Value Check
        console.log("New veFPIS balance in Smart Wallet: ", revestVe.getValue(fnftId));
    }

    /**Jos
     * This test case focus on if user can extend the locking period on the vault
     */
    function testExtendLockingPeriod() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint fee = 1 wei;
        uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.lockTokens(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Skipping two weeks of timestamp
        uint timeSkip = (2 * 7 * 60 * 60 * 24); // 2 week years
        skip(timeSkip);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Calculating expiration time for new extending time
        time = block.timestamp;
        expiration = time + (4 * 365 * 60 * 60 * 24 - 3600); // 4 year in future in future

        //Attempt to extend FNFT Maturity
        hoax(fpisWhale);
        revest.extendFNFTMaturity(fnftId, expiration);
    }

    /**
     * This test case focus on if user can unlock and withdaw their fnft
     */
    function testUnlockAndWithdraw() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint fee = 1 wei;
        uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.lockTokens(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Original balance of FPIS after depositing the FNFT
        uint oriFPIS = FPIS.balanceOf(fpisWhale);

        //Destroying teh address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Skipping two weeks of timestamp
        uint timeSkip = (2 * 365 * 60 * 60 * 24 + 1); // 2 week years
        skip(timeSkip);
        
         //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Unlocking and withdrawing the NFT
        hoax(fpisWhale);
        revest.withdrawFNFT(fnftId, 1);
        uint currentFPIS = FPIS.balanceOf(fpisWhale);

        //Value check
        console.log("Original balance of FPIS: ", oriFPIS);
        console.log("Current balance of FPIS: ", currentFPIS);
    }

    function claimYieldI() public {
        public
    }
}
