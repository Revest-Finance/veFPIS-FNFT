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
    address public DISTRIBUTOR = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6; 
    address public constant REWARD_TOKEN = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    address public veFPISAdmin = 0x6A7efa964Cf6D9Ab3BC3c47eBdDB853A8853C502;
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
        revestVe  = new RevestVeFPIS(Provider, VOTING_ESCROW, DISTRIBUTOR, admin);
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
        uint amount = 1.1e18; //FPIS 

        //Mint the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);

        uint expectedValue = revestVe.getValue(fnftId);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Check
        assert(expectedValue >= 2e18);

        //Logging
        console.log("veFPIS balance should be around 2e18: ", expectedValue);
        console.log("SmartWallet add at address: ", smartWalletAddress);
        console.log("The minted FNFT has the ID: ", fnftId);
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
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //veFXS Balance after first time deposit
        uint oriVeFPIS = revestVe.getValue(fnftId);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Deposit additional fund for FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        revest.depositAdditionalToFNFT(fnftId, amount, 1);

        //Check
        assert(revestVe.getValue(fnftId) > oriVeFPIS);

        //Logging
        console.log("Original veFPIS balance in Smart Wallet: ", oriVeFPIS);
        console.log("New veFPIS balance in Smart Wallet: ", revestVe.getValue(fnftId));
    }

    /**Jos
     * This test case focus on if user can extend the locking period on the vault
     */
    function testExtendLockingPeriod() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Skipping two weeks of timestamp
        uint timeSkip = (2 * 7 * 60 * 60 * 24); // 2 week years
        skip(timeSkip);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Calculating expiration time for new extending time
        time = block.timestamp;
        uint overly_expiration = time + (5 * 365 * 60 * 60 * 24 - 3600); //5 years in the future
        expiration = time + (4 * 365 * 60 * 60 * 24 - 3600); // 4 years in future in future

        //attempt to extend FNFT Maturity more than 2 year max
        hoax(fpisWhale);
        vm.expectRevert("Max lockup is 4 years");
        revest.extendFNFTMaturity(fnftId, overly_expiration);

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
        uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
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

        //Check
        assertEq(currentFPIS - oriFPIS, 1e18);

        //Value check
        console.log("Original balance of FPIS: ", oriFPIS);
        console.log("Current balance of FPIS: ", currentFPIS);
    }

    /**
     * This test case focus on if user can receive yield from their fnft and if we receive fee 
     */
    function testClaimYield() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint amount = 1e18; //FXS  

        //Minting the FNFT and Checkpoint for Yield Distributor
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);
        // hoax(fxsWhale);
        // IYieldDistributor(DISTRIBUTOR).checkpointOtherUser(smartWalletAddress);

        //Original balance of FXS before claiming yield
        uint oriFPIS = FPIS.balanceOf(fpisWhale);

        //Skipping one years of timestamp
        uint timeSkip = (1 * 365 * 60 * 60 * 24 + 1); //s 2 years
        skip(timeSkip);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Yield Claim check
        hoax(fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);

        //Claim yield
        hoax(fpisWhale);
        revestVe.triggerOutputReceiverUpdate(fnftId, bytes(""));
        
        //Balance of FXS after claiming yield
        uint curFPIS = FPIS.balanceOf(fpisWhale);

        //Balance of Revest Reward REceive Address:
        address revestRewardReceiver = 0xA4E7f2a1EDB5AD886baA09Fb258F8ACA7c934ba6;
        uint feeFPIS = FPIS.balanceOf(revestRewardReceiver);

        //Checker
        assertGt(yieldToClaim, 0);
        assertGt(feeFPIS, 0);
        assertEq(curFPIS, oriFPIS + yieldToClaim - feeFPIS);

        //Console
        console.log("Yield to claim: ", yieldToClaim);
        console.log("Original balance of FPIS: ", oriFPIS);
        console.log("Current balance of FPIS: ", curFPIS);
    }

    /**
     * This test case focus on if a user can migrate their existing lock into a fnft
     */
    function testMigrateExistingLock() public {
        uint amount = 1e18; //FPIS  

        //Depositing to veFPIS traditionally
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(VOTING_ESCROW, amount);
        hoax(fpisWhale, fpisWhale);
        IVotingEscrow(VOTING_ESCROW).create_lock(amount, block.timestamp + (2 * 365 * 60 * 60 * 24));
        hoax(fpisWhale, fpisWhale);
        IYieldDistributor(DISTRIBUTOR).checkpoint();

        //Balance of user before migration
        uint userVeBalanceBeforeMigrate = veFPIS.balanceOf(fpisWhale);

        //Toggle on appTransferFromEnabled so that we can migrate lock
        hoax(veFPISAdmin);
        IVotingEscrow(VOTING_ESCROW).toggleTransferToApp();

        //Toggler on proxyAddsEnabled for proxy_slash
        hoax(veFPISAdmin);
        IVotingEscrow(VOTING_ESCROW).toggleProxyAdds();

        //Whitelist proxy as an admin level
        hoax(veFPISAdmin);
        IVotingEscrow(VOTING_ESCROW).adminSetProxy(address(revestVe));

        //Whitelist proxy as a staker level
        hoax(fpisWhale);
        IVotingEscrow(VOTING_ESCROW).stakerSetProxy(address(revestVe));


        //Migrating veFPIS from traditional lock to fnft
        hoax(fpisWhale);
        fnftId = revestVe.migrateExistingLock();
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Balance of user and smart wallet after migration
        uint userVeBalanceAfterMigrate = veFPIS.balanceOf(fpisWhale);
        uint smartWalletBalanceAfterMigrate = veFPIS.balanceOf(smartWalletAddress);

        //Checker
        assertGt(userVeBalanceBeforeMigrate, 0);
        assertEq(userVeBalanceAfterMigrate, 0);
        assertEq(smartWalletBalanceAfterMigrate, userVeBalanceBeforeMigrate);

        //Logging
        console.log("veFPIS balance of user before migrate: ", userVeBalanceBeforeMigrate);
        console.log("veFPIS balance of user after migrate: ", userVeBalanceAfterMigrate);
        console.log("veFPIS balance of smart wallter after migrate: ", smartWalletBalanceAfterMigrate);
    }


    /**
     * This test case focus on if the getOutputDisplayValue() output correctly
     */
    function testOutputDisplay() public {
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        uint amount = 1e18; //FXS  

        //Minting the FNFT and Checkpoint for Yield Distributor
        hoax(fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount); 
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Skipping one years of timestamp
        uint timeSkip = (1 * 365 * 60 * 60 * 24 + 1); //s 2 years
        skip(timeSkip);

         //Yield Claim check
        hoax(fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);

        //Getting output display values
        bytes memory displayData = revestVe.getOutputDisplayValues(fnftId);
        (address adr, string memory rewardDesc, bool hasRewards, uint maxExtensions, address token, int128 lockedBalance) = abi.decode(displayData, (address, string, bool, uint, address, int128));

        string memory par1 = string(abi.encodePacked(RevestHelper.getName(REWARD_TOKEN),": "));
        string memory par2 = string(abi.encodePacked(RevestHelper.amountToDecimal(yieldToClaim, REWARD_TOKEN), " [", RevestHelper.getTicker(REWARD_TOKEN), "] Tokens Available"));
        string memory expectedRewardsDesc = string(abi.encodePacked(par1, par2));

        //checker
        assertEq(adr, smartWalletAddress);
        assertEq(rewardDesc, expectedRewardsDesc);
        assertEq(hasRewards, yieldToClaim > 0);
        assertEq(token, address(FPIS));
        assertEq(lockedBalance, 1e18);

        //Logging
        console.log(adr);
        console.logString(rewardDesc);
        console.log(hasRewards);
        console.log(maxExtensions);
        console.log(token);
        console.logInt(lockedBalance);
    }

    // _____________________________________ Below are additional basic test for the contract ___________________________

    /**
     * 
     */
    function testAddressRegistry() public {
        //Getter Method test
        address addressRegistry = revestVe.getAddressRegistry();
        assertEq(addressRegistry, Provider, "Address Registry is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setAddressRegistry(address(0xdead));

        //Setter Method test
        hoax(revestVe.owner());
        revestVe.setAddressRegistry(address(0xdead));
        address newAddressRegistry = revestVe.getAddressRegistry();
        assertEq(newAddressRegistry, address(0xdead), "New Address Registry is not set correctly!");
    }

    function testRevestAdmin() public {
        //Getter Method test
        address revestAdmin = revestVe.ADMIN();
        assertEq(revestAdmin, admin, "Revest Admin is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setRevestAdmin(address(0));

        //Setter Method test
        hoax(revestVe.owner());
        revestVe.setRevestAdmin(address(0xdead));
        address newAddressRegistry = revestVe.ADMIN();
        assertEq(newAddressRegistry, address(0xdead), "New revest admin is not set correctly");
    }

    function testAsset() public {
        //Getter Method test
        address asset = revestVe.getAsset(0);
        assertEq(asset, VOTING_ESCROW, "Asset/Underlying Ve contract is incorrect");
    }

    function testWeiFee() public {
        //Getter Method  test
        uint weiFee = revestVe.getFlatWeiFee(fpisWhale);
        assertEq(weiFee, 1 ether, "Current weiFee is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setWeiFee(2 ether);
        
         //Setter Method test
        hoax(revestVe.owner());
        revestVe.setWeiFee(2 ether);
        uint newWeiFee = revestVe.getFlatWeiFee(fpisWhale);
        assertEq(newWeiFee, 2 ether, "New wei fei is not set correctly");
    }

    function testERC20Fee() public {
        //Getter Method
        uint fee = revestVe.getERC20Fee(fpisWhale);
        assertEq(fee, 0, "Current fee percentage is incorrect!"); 
    }

    function testMetaData() public {
        //Getter Method
        string memory metadata = revestVe.getCustomMetadata(0);
        assertEq(metadata, "https://revest.mypinata.cloud/ipfs/QmXYdhFqtKFtYW9aEQ8cpPKTm3T1Dv3Hd1uz9ZuYpzeN89", "Metadata is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setMetadata("https://revest.mypinata.cloud/ipfs/fake");

        //Setter Method test
        hoax(address(revestVe.owner()));
        revestVe.setMetadata("https://revest.mypinata.cloud/ipfs/fake");
        string memory newMetadata = revestVe.getCustomMetadata(0);
        assertEq(newMetadata, "https://revest.mypinata.cloud/ipfs/fake", "Metadata is not set correctly!");
    }

    function testHandleFNFTRemaps() public {
        vm.expectRevert("Not applicable");
        revestVe.handleFNFTRemaps(0, new uint[](0), address(0xdead), false);
    }

    function testRescueNativeFunds() public {
        //Fund the contract some money that is falsely allocated
        vm.deal(address(revestVe), 10 ether);
        assertEq(address(revestVe).balance, 10 ether, "Amount of fund does not match!");

        //Calling rescue fund from not owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.rescueNativeFunds();

        //Balance of Revest Owner before rescueing fund
        uint initialBalance = address(revestVe.owner()).balance;

        //Rescue native fund
        hoax(revestVe.owner(), revestVe.owner());
        revestVe.rescueNativeFunds();
        uint currentBalance = address(revestVe.owner()).balance;
        assertGt(currentBalance, initialBalance, "Fund has not been withdrawn to revest owner!");
    }

    function testRescueERC20() public {
        //Fund the contract some money that is false allocated #PEPE
        ERC20 PEPE = ERC20(0x6982508145454Ce325dDbE47a25d4ec3d2311933);

        deal(address(PEPE), address(revestVe), 10 ether);
        assertEq(PEPE.balanceOf(address(revestVe)), 10 ether, "Amount of fund does not match!");

        //Calling rescue fund from not owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.rescueERC20(address(PEPE));


        //Balance of Revest Owner before rescueing fund
        uint initialBalance = PEPE.balanceOf(revestVe.owner());

        //Rescue PEPE
        hoax(revestVe.owner(), revestVe.owner());
        revestVe.rescueERC20(address(PEPE));
        uint currentBalance = PEPE.balanceOf(revestVe.owner());

        assertGt(currentBalance, initialBalance, "Fund has not been withdrawn to revest owner!");
    }

    receive() external payable {

    }
}
