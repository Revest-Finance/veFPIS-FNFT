// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "contracts/RevestVeFPIS.sol";
import "contracts/VestedEscrowSmartWallet.sol";
import "contracts/SmartWalletWhitelistV3.sol";
import "contracts/interfaces/IVotingEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


interface Revest {
    function withdrawFNFT(uint tokenUID, uint quantity) external;
    function depositAdditionalToFNFT(uint fnftId, uint amount,uint quantity) external returns (uint);
    function extendFNFTMaturity(uint fnftId,uint endTime ) external returns (uint);
    function modifyWhitelist(address contra, bool listed) external;

}

contract veFPISRevest is Test {
    address public PROVIDER = 0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public VOTING_ESCROW = 0x574C154C83432B0A45BA3ad2429C3fA242eD7359;
    address public DISTRIBUTOR = 0xE6D31C144BA99Af564bE7E81261f7bD951b802F6; 
    address public constant REWARD_TOKEN = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    address public veFPISAdmin = 0x6A7efa964Cf6D9Ab3BC3c47eBdDB853A8853C502;
    address public revestOwner = 0x801e08919a483ceA4C345b5f8789E506e2624ccf;

    Revest revest = Revest(0x9f551F75DB1c301236496A2b4F7CeCb2d1B2b242);
    ERC20 FPIS = ERC20(0xc2544A32872A91F4A553b404C6950e89De901fdb);

    RevestVeFPIS revestVe;
    SmartWalletWhitelistV3 smartWalletChecker;
    IVotingEscrow veFPIS =  IVotingEscrow(VOTING_ESCROW);

    address admin = makeAddr("admin");
    address fpisWhale = 0x89623FBA59e54c9863346b4d27F0f86369Da11E5;

    address fpisMultisig = 0x6A7efa964Cf6D9Ab3BC3c47eBdDB853A8853C502;

    uint MANAGEMENT_FEE = 5;
    uint PERFORMANCE_FEE = 100;

    uint immutable PERCENTAGE = 1000;

    uint fnftId;
    uint fnftId2;

    address smartWalletAddress;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");


    function setUp() public {
        uint fork1 = vm.createFork("https://mainnet.infura.io/v3/08cfb263de5249ba9bb25868d93d0d45", 17389890);
        vm.selectFork(fork1);

        smartWalletChecker = new SmartWalletWhitelistV3(fpisMultisig);
        revestVe  = new RevestVeFPIS(PROVIDER, VOTING_ESCROW, DISTRIBUTOR, admin, address(smartWalletChecker));
        
        hoax(fpisMultisig, fpisMultisig);
        smartWalletChecker.grantRole(ADMIN_ROLE, address(revestVe));

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
    function testMint(uint amount) public {
        //Fuzz Set-up
        uint fpisBalance = FPIS.balanceOf(address(fpisWhale));
        vm.assume(amount >= 1e18 && amount <= fpisBalance);

        //expiration for fnft config 
        uint expiration = block.timestamp + (2 * 365 * 60 * 60 * 24); // 2 years 

        //Mint the FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);

        uint expectedValue = revestVe.getValue(fnftId);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Check
        assertGt(expectedValue, 2e18, "Deposit value is lower than expected!");
        assertEq(FPIS.balanceOf(fpisWhale), fpisBalance - amount, "FPIS balance is not correct!");

        //Logging
        console.log("veFPIS balance should be around 2e18: ", expectedValue);
        console.log("SmartWallet add at address: ", smartWalletAddress);
        console.log("The minted FNFT has the ID: ", fnftId);
    }

    /**
     * This test case focus on if the admin can receive the management fee up front
     */
    function testReceiveManagementFee(uint amount) public {
        //Fuzz Set-up
        uint fpisBalance = FPIS.balanceOf(address(fpisWhale));
        vm.assume(amount >= 1e18 && amount <= fpisBalance);

        //Expiration for fnft config 
        uint expiration = block.timestamp + (2 * 365 * 60 * 60 * 24); // 2 years 

        //Balance of admin before the minting the lock
        uint oriBal = FPIS.balanceOf(address(admin));

        //Minting the FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);

        //Check
        uint expectedFee = amount * MANAGEMENT_FEE / PERCENTAGE;
        assertEq(FPIS.balanceOf(address(admin)), expectedFee, "Amount of fee received is incorrect!"); 
        assertEq(FPIS.balanceOf(fpisWhale), fpisBalance - amount, "FPIS balance is not correct!");

        //Logging
        console.log("FPIS balance of revest admin before minting: ", oriBal);
        console.log("FPIS balance of revest admin after minting: ", FPIS.balanceOf(address(admin)));
    }

    /**
     * This test case focus on if user can deposit additional amount into the vault
     */
    function testDepositAdditional(uint amount, uint additionalDepositAmount) public {
        //Fuzz Set-up
        uint fpisBalance = FPIS.balanceOf(address(fpisWhale));
        vm.assume(amount >= 1e18 && amount <= fpisBalance);
        uint additionalDepositMax = fpisBalance - amount;
        vm.assume(additionalDepositAmount >0 && additionalDepositAmount <=additionalDepositMax);

        //Expiration for fnft config 
        uint expiration = block.timestamp + (2 * 365 * 60 * 60 * 24); // 2 years 

        //Minting the FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //veFXS Balance after first time deposit
        uint oriVeFPIS = revestVe.getValue(fnftId);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Deposit additional fund for FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), additionalDepositAmount);
        hoax(fpisWhale, fpisWhale);
        revest.depositAdditionalToFNFT(fnftId, additionalDepositAmount, 1);
        destroyAccount(smartWalletAddress, address(admin));

        //Check
        assertGt(revestVe.getValue(fnftId), oriVeFPIS, "Additional deposit not success!");

        //Logging
        console.log("Original veFPIS balance in Smart Wallet: ", oriVeFPIS);
        console.log("New veFPIS balance in Smart Wallet: ", revestVe.getValue(fnftId));

        //Skip 2 years
        skip(52 weeks * 2 + 1 weeks);
        hoax(fpisWhale, fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);
        assertGt(yieldToClaim, 0, "No yield to claim!");
        hoax(fpisWhale, fpisWhale);
        revest.withdrawFNFT(fnftId, 1);
    }

    /**Jos
     * This test case focus on if user can extend the locking period on the vault
     */
    function testExtendLockingPeriod(uint amount) public {
        vm.assume(amount >= 1e18 && amount <= FPIS.balanceOf(fpisWhale));
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 
        // uint amount = 1e18; //FPIS  

        //Minting the FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Checking initial maturity of the lock after deposit
        ILockManager lockManager = ILockManager(IAddressRegistry(PROVIDER).getLockManager());
        uint initialMaturity = lockManager.fnftIdToLock(fnftId).timeLockExpiry;

        //Skipping two weeks of timestamp
        uint timeSkip = (2 * 7 * 60 * 60 * 24); // 2 years
        skip(timeSkip);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Calculating expiration time for new extending time
        time = block.timestamp;
        uint overly_expiration = time + (5 * 365 * 60 * 60 * 24 - 3600); //5 years in the future
        expiration = time + (4 * 365 * 60 * 60 * 24 - 3600); // 4 years in future in future

        //attempt to extend FNFT Maturity more than 2 year max
        hoax(fpisWhale, fpisWhale);
        vm.expectRevert("Max lockup is 4 years");
        revest.extendFNFTMaturity(fnftId, overly_expiration);

        //Attempt to extend FNFT Maturity
        hoax(fpisWhale, fpisWhale);
        revest.extendFNFTMaturity(fnftId, expiration);
        destroyAccount(smartWalletAddress, address(admin));

        //Checking after-extend maturity of the lock after deposit
        uint currentMaturity = lockManager.fnftIdToLock(fnftId).timeLockExpiry;

        //Check
        assertGt(currentMaturity, initialMaturity, "Maturity has not been changed!");

        //Skip 4 years to end of period
        skip(52 weeks * 4 + 1 weeks);
        hoax(fpisWhale, fpisWhale);
        revest.withdrawFNFT(fnftId, 1);

        //Locking
        console.log("Initual Maturity: ", initialMaturity);
        console.log("Current Maturity: ", currentMaturity);
    }

    /**
     * This test case focus on if user can unlock and withdaw their fnft, and plus claim fee
     */
    function testUnlockAndWithdraw(uint amount) public {
        vm.assume(amount >= 1e18 && amount <= FPIS.balanceOf(fpisWhale));
        // Outline the parameters that will govern the FNFT
        uint time = block.timestamp;
        uint expiration = time + (2 * 365 * 60 * 60 * 24); // 2 years 


        //Minting the FNFT
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Original balance of FXS and after depositing the FNFT
        uint oriFXS = FPIS.balanceOf(fpisWhale);
        uint oriFeeReceived = FPIS.balanceOf(address(admin));

        //Destroying teh address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Skipping two weeks of timestamp
        uint timeSkip = (2 * 365 * 60 * 60 * 24 + 1); // 2 years
        skip(timeSkip);
        
        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Yield Claim check
        hoax(fpisWhale, fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);

        //Unlocking and withdrawing the NFT
        hoax(fpisWhale, fpisWhale);
        revest.withdrawFNFT(fnftId, 1);
        
        //Balance of FXS after claiming yield
        uint curFXS = FPIS.balanceOf(fpisWhale);
        uint curFeeReceived = FPIS.balanceOf(address(admin));

        // Fee
        uint performanceFee = yieldToClaim * PERFORMANCE_FEE / PERCENTAGE;
        uint managementFee = amount * MANAGEMENT_FEE / PERCENTAGE;

        //Check
        assertEq(curFXS, oriFXS + amount + yieldToClaim - performanceFee - managementFee, "Does not receive enough yield!");
        assertGt(curFeeReceived, oriFeeReceived, "Admin does not receieve performance fee!");

        //Logging
        console.log("Original balance of FXS: ", oriFXS);
        console.log("Current balance of FXS: ", curFXS);
        console.log("Performance Fee: ", performanceFee);
        console.log("Management Fee: ", managementFee);
    }

    /**
     * This test case focus on if user can receive yield from their fnft
     */
    function testClaimYield(uint amount) public {
        //Fuzz Set-up
        uint fpisBalance = FPIS.balanceOf(address(fpisWhale));
        vm.assume(amount >= 1e18 && amount <= fpisBalance);

        //Expiration for fnft config 
        uint expiration = block.timestamp + (2 * 365 * 60 * 60 * 24); // 2 years 

        //Minting the FNFT and Checkpoint for Yield Distributor
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount);
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Original balance of FXS before claiming yield
        uint oriFPIS = FPIS.balanceOf(fpisWhale);
        uint oriFeeReceived = FPIS.balanceOf(address(admin));

        //Skipping one years of timestamp
        uint timeSkip = (1 * 365 * 60 * 60 * 24 + 1); // 1 year
        skip(timeSkip);

        //Destroy the address of smart wallet for testing purpose
        destroyAccount(smartWalletAddress, address(admin));

        //Yield Claim check
        hoax(fpisWhale, fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);

        //Claim yield
        hoax(fpisWhale, fpisWhale);
        revestVe.triggerOutputReceiverUpdate(fnftId, bytes(""));
        
        //Balance of FXS after claiming yield
        uint curFPIS = FPIS.balanceOf(fpisWhale);
        uint curFeeReceived = FPIS.balanceOf(address(admin));

        //Performance Fee
        uint performanceFee = yieldToClaim * PERFORMANCE_FEE / PERCENTAGE;

        //Checker
        assertGt(yieldToClaim, 0, "Yield should be greater than 0!");
        assertEq(curFPIS, oriFPIS + yieldToClaim - performanceFee, "Does not receive enough yield!");
        assertGt(curFeeReceived, oriFeeReceived, "Admin does not receieve performance fee!");

        //Console
        console.log("Yield to claim: ", yieldToClaim);
        console.log("Original balance of FPIS from user: ", oriFPIS);
        console.log("Original balance of FPIS from rewardHandler: ", oriFeeReceived);
        console.log("Performance fee: ", performanceFee);
        console.log("Current balance of FPIS from userS: ", curFPIS);
        console.log("Current balance of FPIS from rewardHandler: ", curFeeReceived);
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
        hoax(fpisWhale, fpisWhale);
        IVotingEscrow(VOTING_ESCROW).stakerSetProxy(address(revestVe));


        //Migrating veFPIS from traditional lock to fnft
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.migrateExistingLock();
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Balance of user and smart wallet after migration
        uint userVeBalanceAfterMigrate = veFPIS.balanceOf(fpisWhale);
        uint smartWalletBalanceAfterMigrate = veFPIS.balanceOf(smartWalletAddress);

        //Checker
        assertGt(userVeBalanceBeforeMigrate, 0, "User has not locked FPIS!");
        assertEq(userVeBalanceAfterMigrate, 0, "veFPIS has not been transfered/ completely transfered!");
        assertEq(smartWalletBalanceAfterMigrate, userVeBalanceBeforeMigrate, "Amount of veFPIS does not match between the smart wallet and the before-migrate lock!");

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
        hoax(fpisWhale, fpisWhale);
        FPIS.approve(address(revestVe), amount);
        hoax(fpisWhale, fpisWhale);
        fnftId = revestVe.createNewLock(expiration, amount); 
        smartWalletAddress = revestVe.getAddressForFNFT(fnftId);

        //Skipping one years of timestamp
        uint timeSkip = (1 * 365 * 60 * 60 * 24 + 1); //s 2 years
        skip(timeSkip);

         //Yield Claim check
        hoax(fpisWhale, fpisWhale);
        uint yieldToClaim = IYieldDistributor(DISTRIBUTOR).earned(smartWalletAddress);

        //Getting output display values
        bytes memory displayData = revestVe.getOutputDisplayValues(fnftId);
        (address adr, string memory rewardDesc, bool hasRewards, uint maxExtensions, address token, int128 lockedBalance) = abi.decode(displayData, (address, string, bool, uint, address, int128));

        string memory par1 = string(abi.encodePacked(RevestHelper.getName(REWARD_TOKEN),": "));
        string memory par2 = string(abi.encodePacked(RevestHelper.amountToDecimal(yieldToClaim, REWARD_TOKEN), " [", RevestHelper.getTicker(REWARD_TOKEN), "] Tokens Available"));
        string memory expectedRewardsDesc = string(abi.encodePacked(par1, par2));

        //checker
        assertEq(adr, smartWalletAddress, "Encoded address is incorrect!");
        assertEq(rewardDesc, expectedRewardsDesc, "Reward description is incorrect!");
        assertEq(hasRewards, yieldToClaim > 0, "Encoded hasRewards is incorrect!");
        assertEq(token, address(FPIS), "Encoded vault token is incorrect!");
        assertEq(lockedBalance, 995000000000000000, "Encoded locked balance is incorrect!"); // 95% of amount, (5% of management fee)

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
        assertEq(addressRegistry, PROVIDER, "Address Registry is incorrect!");

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
        address revestAdmin = revestVe.ADMIN_WALLET();
        assertEq(revestAdmin, admin, "Revest Admin is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setRevestAdmin(address(0));

        //Setter Method test
        hoax(revestVe.owner());
        revestVe.setRevestAdmin(address(0xdead));
        address newAddressRegistry = revestVe.ADMIN_WALLET();
        assertEq(newAddressRegistry, address(0xdead), "New revest admin is not set correctly");
    }

    function testAsset() public {
        //Getter Method test
        address asset = revestVe.getAsset(0);
        assertEq(asset, VOTING_ESCROW, "Asset/Underlying Ve contract is incorrect");
    }

    function testPerformanceFee() public {
        //Getter Method  test
        uint weiFee = revestVe.getFlatWeiFee(fpisWhale);
        assertEq(weiFee, PERFORMANCE_FEE, "Current weiFee is incorrect!");

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setPerformanceFee(2 ether);
        
         //Setter Method test
        hoax(revestVe.owner());
        revestVe.setPerformanceFee(2 ether);
        uint newWeiFee = revestVe.getFlatWeiFee(fpisWhale);
        assertEq(newWeiFee, 2 ether, "New wei fei is not set correctly");
    }

    function testManagementFee() public {
        //Getter Method
        uint fee = revestVe.getERC20Fee(fpisWhale);
        assertEq(fee, MANAGEMENT_FEE, "Current fee percentage is incorrect!"); //10%

        //Calling from non-owner
        hoax(address(0xdead));
        vm.expectRevert("Ownable: caller is not the owner");
        revestVe.setManagementFee(20);
 
        //Setter Method test
        hoax(revestVe.owner());
        revestVe.setManagementFee(20);
        uint newFee = revestVe.getERC20Fee(fpisWhale);
        assertEq(newFee, 20, "New fee percentage is not set correctly!");
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
