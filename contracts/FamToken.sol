// SPDX-License-Identifier: MIT
// FamToken.sol - Platform Token + Creator Keys Trading System
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FamToken is ERC20, Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant PLATFORM_FEE_PERCENT = 5; // 5%
    uint256 public constant CREATOR_FEE_PERCENT = 5; // 5% on trades
    uint256 public constant INITIAL_CREATOR_FEE_PERCENT = 20; // 20% on first buy
    uint256 public constant TAX_RATE = 50; // 5% (50/1000) on token transfers
    
    // Adjustable parameters
    uint256 public creatorRegistrationFee = 1_000 * 10**18; // 1,000 FAM tokens (adjustable)
    uint256 public maxCreatorKeys = 1_000; // Max keys creator can sell directly (adjustable)
    
    // Creator structure
    struct Creator {
        address creatorAddress;
        string name;
        string bio;
        bool isActive;
        uint256 keysSupply;
        uint256 totalVolume;
        uint256 registrationTime;
        uint256 keysSoldDirectly; // Track direct sales from creator
    }
    
    // Storage
    mapping(address => Creator) public creators;
    mapping(address => mapping(address => uint256)) public keysBalance; // user => creator => keys
    mapping(address => bool) public isCreator;
    address[] public creatorList;
    
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    mapping(address => bool) public taxExempt;
    
    address public stakingVault; // Address to receive platform fees (staking rewards pool)
    
    uint256 public platformFeesCollected;
    
    // Events
    event CreatorRegistered(address indexed creator, string name, uint256 fee);
    event MaxCreatorKeysUpdated(uint256 oldMax, uint256 newMax);
    event RegistrationFeeUpdated(uint256 oldFee, uint256 newFee);
    event KeysBought(
        address indexed buyer,
        address indexed creator,
        uint256 amount,
        uint256 price,
        uint256 platformFee,
        uint256 creatorFee
    );
    event KeysSold(
        address indexed seller,
        address indexed creator,
        uint256 amount,
        uint256 price,
        uint256 platformFee,
        uint256 creatorFee
    );
    event TaxApplied(address indexed from, uint256 amount, uint256 burned, uint256 vaulted);
    
    constructor(address _stakingVault) ERC20("Fam", "FAM") Ownable(msg.sender) {
        require(_stakingVault != address(0), "Invalid staking vault");
        stakingVault = _stakingVault;
        
        // Mint initial supply: 21M FAM tokens
        _mint(msg.sender, 21_000_000 * 10**18);
        
        // Exempt deployer from transfer taxes for testing
        taxExempt[msg.sender] = true;
        
        // Exempt contract from taxes
        taxExempt[address(this)] = true;
    }
    
    // Register as a creator (costs adjustable FAM tokens)
    function registerCreator(string memory _name, string memory _bio) external {
        require(!isCreator[msg.sender], "Already registered");
        require(bytes(_name).length > 0, "Name required");
        require(balanceOf(msg.sender) >= creatorRegistrationFee, "Insufficient FAM tokens");
        
        // Burn registration fee (removes tokens from circulation)
        _burn(msg.sender, creatorRegistrationFee);
        
        creators[msg.sender] = Creator({
            creatorAddress: msg.sender,
            name: _name,
            bio: _bio,
            isActive: true,
            keysSupply: 0,
            totalVolume: 0,
            registrationTime: block.timestamp,
            keysSoldDirectly: 0
        });
        
        isCreator[msg.sender] = true;
        creatorList.push(msg.sender);
        
        emit CreatorRegistered(msg.sender, _name, creatorRegistrationFee);
    }
    
    // Get price for buying keys (bonding curve)
    function getBuyPrice(address creator, uint256 amount) public view returns (uint256) {
        require(isCreator[creator], "Not a creator");
        return getPrice(creators[creator].keysSupply, amount);
    }
    
    // Get price for selling keys (bonding curve)
    function getSellPrice(address creator, uint256 amount) public view returns (uint256) {
        require(isCreator[creator], "Not a creator");
        require(creators[creator].keysSupply >= amount, "Insufficient supply");
        return getPrice(creators[creator].keysSupply - amount, amount);
    }
    
    // Bonding curve formula: price = supply^2 / 16000 (in FAM tokens)
    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * supply * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = (supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000; // Price in FAM tokens (18 decimals)
    }
    
    // Buy keys using FAM tokens
    function buyKeys(address creator, uint256 amount) external nonReentrant {
        require(isCreator[creator], "Not a creator");
        require(amount > 0, "Amount must be positive");
        
        // Check if creator has reached direct sales limit
        require(
            creators[creator].keysSoldDirectly + amount <= maxCreatorKeys,
            "Creator reached direct sales limit. Buy from other fans!"
        );
        
        uint256 price = getBuyPrice(creator, amount);
        
        // Calculate fees
        bool isFirstBuy = creators[creator].keysSupply == 0;
        uint256 creatorFeePercent = isFirstBuy ? INITIAL_CREATOR_FEE_PERCENT : CREATOR_FEE_PERCENT;
        
        uint256 platformFee = (price * PLATFORM_FEE_PERCENT) / 100;
        uint256 creatorFee = (price * creatorFeePercent) / 100;
        uint256 totalCost = price + platformFee + creatorFee;
        
        require(balanceOf(msg.sender) >= totalCost, "Insufficient FAM tokens");
        
        // Transfer FAM tokens
        _transfer(msg.sender, address(this), totalCost);
        
        // Update balances
        keysBalance[msg.sender][creator] += amount;
        creators[creator].keysSupply += amount;
        creators[creator].totalVolume += price;
        creators[creator].keysSoldDirectly += amount; // Track direct sales
        
        // Distribute fees (tokens held by contract)
        platformFeesCollected += platformFee;
        
        // Creator gets their fee tokens
        _transfer(address(this), creator, creatorFee);
        
        emit KeysBought(msg.sender, creator, amount, price, platformFee, creatorFee);
    }
    
    // Sell keys back for FAM tokens
    function sellKeys(address creator, uint256 amount) external nonReentrant {
        require(isCreator[creator], "Not a creator");
        require(amount > 0, "Amount must be positive");
        require(keysBalance[msg.sender][creator] >= amount, "Insufficient keys");
        
        uint256 price = getSellPrice(creator, amount);
        
        // Calculate fees
        uint256 platformFee = (price * PLATFORM_FEE_PERCENT) / 100;
        uint256 creatorFee = (price * CREATOR_FEE_PERCENT) / 100;
        uint256 totalFees = platformFee + creatorFee;
        uint256 netProceeds = price - totalFees;
        
        // Update balances
        keysBalance[msg.sender][creator] -= amount;
        creators[creator].keysSupply -= amount;
        creators[creator].totalVolume += price;
        
        // Distribute fees
        platformFeesCollected += platformFee;
        
        // Creator gets their fee tokens
        _transfer(address(this), creator, creatorFee);
        
        // Send proceeds to seller
        _transfer(address(this), msg.sender, netProceeds);
        
        emit KeysSold(msg.sender, creator, amount, price, platformFee, creatorFee);
    }
    
    // ERC20 transfer with tax (for regular FAM token transfers)
    function transfer(address to, uint256 amount) public override returns (bool) {
        _applyTax(msg.sender, to, amount);
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _applyTax(from, to, amount);
        return super.transferFrom(from, to, amount);
    }
    
    function _applyTax(address from, address to, uint256 amount) internal {
        if (amount == 0 || from == address(0) || to == address(0)) return;
        if (taxExempt[from] || taxExempt[to]) return;
        
        uint256 tax = (amount * TAX_RATE) / 1000; // 5% tax
        uint256 burnAmount = (tax * 3) / 5; // 3% burn
        uint256 vaultAmount = tax - burnAmount; // 2% to platform
        
        // Burn 3%
        _burn(from, burnAmount);
        
        // Platform gets 2%
        platformFeesCollected += vaultAmount;
        
        emit TaxApplied(from, amount, burnAmount, vaultAmount);
    }
    
    // View functions
    function getCreatorInfo(address creator) external view returns (
        string memory name,
        string memory bio,
        bool isActive,
        uint256 keysSupply,
        uint256 totalVolume,
        uint256 registrationTime,
        uint256 keysSoldDirectly
    ) {
        Creator memory c = creators[creator];
        return (c.name, c.bio, c.isActive, c.keysSupply, c.totalVolume, c.registrationTime, c.keysSoldDirectly);
    }
    
    function getKeysBalance(address user, address creator) external view returns (uint256) {
        return keysBalance[user][creator];
    }
    
    function getTotalCreators() external view returns (uint256) {
        return creatorList.length;
    }
    
    function getKeysRemainingForDirectSale(address creator) external view returns (uint256) {
        require(isCreator[creator], "Not a creator");
        uint256 sold = creators[creator].keysSoldDirectly;
        if (sold >= maxCreatorKeys) {
            return 0;
        }
        return maxCreatorKeys - sold;
    }
    
    function getBuyPriceAfterFee(address creator, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(creator, amount);
        bool isFirstBuy = creators[creator].keysSupply == 0;
        uint256 creatorFeePercent = isFirstBuy ? INITIAL_CREATOR_FEE_PERCENT : CREATOR_FEE_PERCENT;
        
        uint256 platformFee = (price * PLATFORM_FEE_PERCENT) / 100;
        uint256 creatorFee = (price * creatorFeePercent) / 100;
        return price + platformFee + creatorFee;
    }
    
    function getSellPriceAfterFee(address creator, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(creator, amount);
        uint256 platformFee = (price * PLATFORM_FEE_PERCENT) / 100;
        uint256 creatorFee = (price * CREATOR_FEE_PERCENT) / 100;
        return price - platformFee - creatorFee;
    }
    
    // Admin functions
    function setTaxExempt(address _address, bool _exempt) external onlyOwner {
        taxExempt[_address] = _exempt;
    }
    
    function updateMaxCreatorKeys(uint256 _newMax) external onlyOwner {
        require(_newMax > 0, "Max must be positive");
        uint256 oldMax = maxCreatorKeys;
        maxCreatorKeys = _newMax;
        emit MaxCreatorKeysUpdated(oldMax, _newMax);
    }
    
    function updateRegistrationFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "Fee must be positive");
        uint256 oldFee = creatorRegistrationFee;
        creatorRegistrationFee = _newFee;
        emit RegistrationFeeUpdated(oldFee, _newFee);
    }
    
    function withdrawPlatformFees() external onlyOwner {
        uint256 amount = platformFeesCollected;
        platformFeesCollected = 0;
        _transfer(address(this), stakingVault, amount);
    }
    
    function setStakingVault(address _newVault) external onlyOwner {
        require(_newVault != address(0), "Invalid vault address");
        stakingVault = _newVault;
    }
    
    function deactivateCreator(address creator) external onlyOwner {
        require(isCreator[creator], "Not a creator");
        creators[creator].isActive = false;
    }
    
    // Emergency function to burn platform fees if needed
    function burnPlatformFees(uint256 amount) external onlyOwner {
        require(amount <= platformFeesCollected, "Insufficient fees");
        platformFeesCollected -= amount;
        _burn(address(this), amount);
    }
}