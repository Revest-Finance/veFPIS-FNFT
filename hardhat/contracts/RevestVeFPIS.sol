// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "./interfaces/IAddressRegistry.sol";
import "./interfaces/IOutputReceiverV3.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IRevest.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IRewardsHandler.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IFeeReporter.sol";
import "./interfaces/IDistributor.sol";
import "./VestedEscrowSmartWallet.sol";
import "./SmartWalletWhitelistV2.sol";

// OZ imports
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

// Libraries
import "./lib/RevestHelper.sol";

interface IWETH {
    function deposit() external payable;
}

/**
 * @title Revest FNFT for veFPIS 
 * @author RobAnon
 * @author Ekkila
 * @dev 
 */
contract RevestVeFPIS is IOutputReceiverV3, Ownable, ERC165, IFeeReporter, ReentrancyGuard {
    
    using SafeERC20 for IERC20;

    // Where to find the Revest address registry that contains info about what contracts live where
    address public addressRegistry;

    // Address of voting escrow contract
    address public immutable VOTING_ESCROW;

    // Token used for voting escrow
    address public immutable TOKEN;

    // Distributor for rewards address
    address public DISTRIBUTOR;

     // Revest Admin Account 
    address public ADMIN_WALLET;

    // veFPIS token    
    address public constant REWARD_TOKEN = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    // Template address for VE wallets
    address public immutable TEMPLATE;

    // The file which tells our frontend how to visually represent such an FNFT
    string public METADATA = "https://revest.mypinata.cloud/ipfs/QmXYdhFqtKFtYW9aEQ8cpPKTm3T1Dv3Hd1uz9ZuYpzeN89";

    // Constant used for approval
    uint private constant MAX_INT = 2 ** 256 - 1;

    uint private constant WEEK = 7 * 86400;

    uint private constant MAX_LOCKUP = 4 * 365 days;

    uint private constant FREE_AMOUNT = 100 ether;

    //Percentage
    uint private constant PERCENTAGE = 1000;

    //Performance Fee
    uint private PERFORMANCE_FEE = 100;

    //Management Fee
    uint private MANAGEMENT_FEE = 5;

    // For tracking if a given contract has approval for token
    mapping (address => mapping (address => bool)) private approvedContracts;

    // For tracking wallet approvals for tokens
    // Works for up to 256 tokens
    mapping (address => mapping (uint => uint)) private walletApprovals;


    // Control variable to let all users utilize smart wallets for proxy execution
    bool public globalProxyEnabled;

    // Control variable to enable a given FNFT to utilize their smart wallet for proxy execution
    mapping (uint => bool) public proxyEnabled;

    // Initialize the contract with the needed valeus
    constructor(address _provider, address _vE, address _distro, address _revestAdmin) {
        addressRegistry = _provider;
        VOTING_ESCROW = _vE;
        DISTRIBUTOR = _distro;
        TOKEN = IVotingEscrow(_vE).token();
        VestedEscrowSmartWallet wallet = new VestedEscrowSmartWallet(_vE, _distro);
        TEMPLATE = address(wallet);
        ADMIN_WALLET = _revestAdmin;
    }

    modifier onlyRevestController() {
        require(msg.sender == IAddressRegistry(addressRegistry).getRevest(), 'Unauthorized Access!');
        _;
    }

    modifier onlyTokenHolder(uint fnftId) {
        IAddressRegistry reg = IAddressRegistry(addressRegistry);
        require(IFNFTHandler(reg.getRevestFNFT()).getBalance(msg.sender, fnftId) > 0, 'E064');
        _;
    }

    // Allows core Revest contracts to make sure this contract can do what is needed
    // Mandatory method
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOutputReceiver).interfaceId
            || interfaceId == type(IOutputReceiverV2).interfaceId
            || interfaceId == type(IOutputReceiverV3).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Create a new lock entirely
     * @param endTime the expiration date for the lock
     * @param amountToLock amount of veFPIS to lock
     */
    function createNewLock(
        uint endTime,
        uint amountToLock
    ) external nonReentrant returns (uint fnftId) {
        //Taking Management Fee
        uint fxsFee = amountToLock * MANAGEMENT_FEE / PERCENTAGE; // Make constant
        IERC20(TOKEN).safeTransferFrom(msg.sender, ADMIN_WALLET, fxsFee);
        amountToLock -= fxsFee;

        // TODO: Emit fee claimed event

        //Mint FNFT
        fnftId = _mintFNFT(endTime);
        
        // We deploy the smart wallet
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);

        // Transfer the tokens from the user to the smart wallet
        IERC20(TOKEN).safeTransferFrom(msg.sender, smartWallAdd, amountToLock);

        // We use our admin powers on SmartWalletWhitelistV2 to approve the newly created smart wallet
        SmartWalletWhitelistV2(IVotingEscrow(VOTING_ESCROW).smart_wallet_checker()).approveWallet(smartWallAdd);

        // We deposit our funds into the wallet
        wallet.createLock(amountToLock, endTime);
        emit DepositERC20OutputReceiver(msg.sender, TOKEN, amountToLock, fnftId, abi.encode(smartWallAdd));
    }

    /// Requires the msg.sender needs to call approve transfer amount on
    /// Requires appTransferFromsEnabled on veFPIS
    function migrateExistingLock() external nonReentrant returns (uint fnftId) {
        IVotingEscrow veFPIS = IVotingEscrow(VOTING_ESCROW);
        (int128 amount, uint endTime) = veFPIS.locked(msg.sender);

        // Mint the FNFT
        fnftId = _mintFNFT(endTime);

        // Deploy the smart wallet
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);

        uint amountToLock = uint(int256(amount));
        // This contract must be approved proxy, both globally and by msg.sender
        veFPIS.transfer_to_app(msg.sender, smartWallAdd, amount);
        veFPIS.proxy_slash(msg.sender, amountToLock);

        // We use our admin powers on SmartWalletWhitelistV2 to approve the newly created smart wallet
        SmartWalletWhitelistV2(IVotingEscrow(VOTING_ESCROW).smart_wallet_checker()).approveWallet(smartWallAdd);

         // We deposit our funds into the wallet
        wallet.createLock(amountToLock, endTime);
        emit DepositERC20OutputReceiver(msg.sender, TOKEN, amountToLock, fnftId, abi.encode(smartWallAdd));
    }


    function receiveRevestOutput(
        uint fnftId,
        address,
        address payable owner,
        uint
    ) external override nonReentrant {
        // Security check to make sure the Revest vault is the only contract that can call this method
        address vault = IAddressRegistry(addressRegistry).getTokenVault();
        require(_msgSender() == vault, 'E016');

        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);

        //claim yield & fee
        wallet.claimRewards(owner, ADMIN_WALLET, PERFORMANCE_FEE);

        //withdraw fund
        wallet.withdraw();
        uint balance = IERC20(TOKEN).balanceOf(address(this));
        IERC20(TOKEN).safeTransfer(owner, balance);

        // Clean up memory
        SmartWalletWhitelistV2(IVotingEscrow(VOTING_ESCROW).smart_wallet_checker()).revokeWallet(smartWallAdd);

        emit WithdrawERC20OutputReceiver(owner, TOKEN, balance, fnftId, abi.encode(smartWallAdd));
    }

    // Not applicable, as these cannot be split
    function handleFNFTRemaps(uint, uint[] memory, address, bool) external pure override {
        require(false, 'Not applicable');
    }

    // Allows custom parameters to be passed during withdrawals
    function receiveSecondaryCallback(
        uint fnftId,
        address payable owner,
        uint quantity,
        IRevest.FNFTConfig memory config,
        bytes memory args
    ) external payable override {}

    // Callback from Revest.sol to extend maturity
    function handleTimelockExtensions(uint fnftId, uint expiration, address) external override onlyRevestController {
        require(expiration - block.timestamp <= MAX_LOCKUP, 'Max lockup is 4 years');
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);
        wallet.increaseUnlockTime(expiration);
    }

    /// Prerequisite: User has approved this contract to spend tokens on their behalf
    function handleAdditionalDeposit(uint fnftId, uint amountToDeposit, uint, address caller) external override nonReentrant onlyRevestController {
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);

        //Taking management fee
        uint fxsFee = amountToDeposit * MANAGEMENT_FEE / PERCENTAGE; // Make constant
        IERC20(TOKEN).safeTransferFrom(msg.sender, ADMIN_WALLET, fxsFee);
        amountToDeposit -= fxsFee;

        IERC20(TOKEN).safeTransferFrom(caller, smartWallAdd, amountToDeposit);
        wallet.increaseAmount(amountToDeposit);
    }

    // Not applicable
    function handleSplitOperation(uint fnftId, uint[] memory proportions, uint quantity, address caller) external override {}

    // Claims rewards on user's behalf
    function triggerOutputReceiverUpdate(
        uint fnftId,
        bytes memory
    ) external override onlyTokenHolder(fnftId) {
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);
        wallet.claimRewards(msg.sender, ADMIN_WALLET, PERFORMANCE_FEE);
    }       

    function proxyExecute(
        uint fnftId,
        address destination,
        bytes memory data
    ) external onlyTokenHolder(fnftId) payable returns (bytes memory dataOut) {
        require(globalProxyEnabled || proxyEnabled[fnftId], 'Proxy access not enabled!');
        address smartWallAdd = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
        VestedEscrowSmartWallet wallet = VestedEscrowSmartWallet(smartWallAdd);
        dataOut = wallet.proxyExecute{value: msg.value}(destination, data);
        wallet.cleanMemory();
    }

    // Utility functions
    function _mintFNFT(uint endTime) internal returns (uint fnftId) {
        /// Mint FNFT
        
        // Initialize the Revest config object
        IRevest.FNFTConfig memory fnftConfig;

        // Want FNFT to be extendable and support multiple deposits
        fnftConfig.isMulti = true;

        fnftConfig.maturityExtension = true;

        // Will result in the asset being sent back to this contract upon withdrawal
        // Results solely in a callback
        fnftConfig.pipeToContract = address(this);  

        // Set these two arrays according to Revest specifications to say
        // Who gets these FNFTs and how many copies of them we should create
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;

        uint[] memory quantities = new uint[](1);
        quantities[0] = 1;

        address revest = IAddressRegistry(addressRegistry).getRevest();
        
        fnftId = IRevest(revest).mintTimeLock(endTime, recipients, quantities, fnftConfig);
    }

    /// Admin Functions

    function setAddressRegistry(address addressRegistry_) external override onlyOwner {
        addressRegistry = addressRegistry_;
    }

    function setDistributor(address _distro) external onlyOwner {
        DISTRIBUTOR = _distro;
    }

    function setRevestAdmin(address _admin) external onlyOwner {
        ADMIN_WALLET = _admin;
    }

    function setPerformanceFee(uint fee) external onlyOwner {
        PERFORMANCE_FEE = fee;
    }

    function setManagementFee(uint fee) external onlyOwner {
        MANAGEMENT_FEE = fee;
    }

    function setMetadata(string memory _meta) external onlyOwner {
        METADATA = _meta;
    }

    function setGlobalProxyEnabled(bool enable) external onlyOwner {
        globalProxyEnabled = enable;
    }

    function setProxyStatusForFNFT(uint fnftId, bool status) external onlyOwner {
        proxyEnabled[fnftId] = status;
    }

    /// If funds are mistakenly sent to smart wallets, this will allow the owner to assist in rescue
    function rescueNativeFunds() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// Under no circumstances should this contract ever contain ERC-20 tokens at the end of a transaction
    /// If it does, someone has mistakenly sent funds to the contract, and this function can rescue their tokens
    function rescueERC20(address token) external onlyOwner {
        uint amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /// View Functions

    function getCustomMetadata(uint) external view override returns (string memory) {
        return METADATA;
    }

    // Will give balance in xLQDR
    function getValue(uint fnftId) public view override returns (uint) {
        return IVotingEscrow(VOTING_ESCROW).balanceOf(Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId))));
    }

    // Must always be in native token
    function getAsset(uint) external view override returns (address) {
        return VOTING_ESCROW;
    }

    function getOutputDisplayValues(uint fnftId) external view override returns (bytes memory displayData) {
         //calculate yield output for certain FNFT 
        uint yield = IYieldDistributor(DISTRIBUTOR).earned(Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId))));
        bool hasRewards =  (yield > 0) ? true : false;

        //Making string to output
        string memory rewardsDesc;
        if(hasRewards) {
            string memory par1 = string(abi.encodePacked(RevestHelper.getName(REWARD_TOKEN),": "));
            string memory par2 = string(abi.encodePacked(RevestHelper.amountToDecimal(yield, REWARD_TOKEN), " [", RevestHelper.getTicker(REWARD_TOKEN), "] Tokens Available"));
            rewardsDesc = string(abi.encodePacked(par1, par2));
        }

        address smartWallet = getAddressForFNFT(fnftId);
        uint maxExtension = block.timestamp / (1 weeks) * (1 weeks) + MAX_LOCKUP; //Ensures no confusion with time zones and date-selectors
        (int128 lockedBalance, ) = IVotingEscrow(VOTING_ESCROW).locked(smartWallet);
        displayData = abi.encode(smartWallet, rewardsDesc, hasRewards, maxExtension, TOKEN, lockedBalance);
    }

    function getAddressRegistry() external view override returns (address) {
        return addressRegistry;
    }

    function getRevest() internal view returns (IRevest) {
        return IRevest(IAddressRegistry(addressRegistry).getRevest());
    }

    function getFlatWeiFee(address) external view override returns (uint) {
        return PERFORMANCE_FEE;
    }

    function getERC20Fee(address) external view override returns (uint) {
        return MANAGEMENT_FEE;
    }

    function getAddressForFNFT(uint fnftId) public view returns (address smartWallAdd) {
        smartWallAdd = Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(TOKEN, fnftId)));
    }
}
