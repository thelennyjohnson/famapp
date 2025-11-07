# FamToken Smart Contract

A comprehensive ERC20 token with integrated creator economy and fan keys trading system built on Ethereum.

## 📋 Overview

FamToken is a dual-purpose smart contract that serves as both:
- **ERC20 Token**: FAM token with deflationary mechanics
- **Creator Platform**: Keys trading marketplace with bonding curves

## 🎯 Key Features

- ✅ **Creator Registration**: Pay FAM tokens to become a creator
- ✅ **Keys Trading**: Buy/sell creator keys using bonding curves
- ✅ **Scarcity Limits**: Creators can sell max 1,000 keys directly
- ✅ **Platform Fees**: 5% on all trades + 5% transfer tax
- ✅ **Staking Integration**: Platform fees sent to staking vault
- ✅ **Adjustable Parameters**: Owner can update fees and limits

## 💰 Tokenomics

### Supply
- **Total Supply**: 21,000,000 FAM
- **Deflationary**: Registration fees burned, transfer tax burns 3%

### Fee Structure
| Action | Platform Fee | Creator Fee | Burn |
|--------|-------------|-------------|------|
| Creator Registration | - | - | 1,000 FAM |
| Key Purchase (First) | 5% | 20% | - |
| Key Purchase (Subsequent) | 5% | 5% | - |
| Key Sale (P2P) | 5% | 5% | - |
| FAM Transfer | 2% | - | 3% |

## 🚀 Deployment

### Constructor Parameters
```solidity
constructor(address _stakingVault)
```

**Parameters:**
- `_stakingVault`: Address to receive platform fees (staking rewards pool)

### Example Deployment
```javascript
// Remix deployment
_stakingVault: "0xYourStakingVaultAddress"

// Hardhat deployment
const stakingVault = "0xYourStakingVaultAddress";
const FamToken = await ethers.getContractFactory("FamToken");
const token = await FamToken.deploy(stakingVault);
```

## 📚 Functions

### Creator Management

#### `registerCreator(string _name, string _bio)`
Register as a creator by burning registration fee.

**Parameters:**
- `_name`: Creator display name
- `_bio`: Creator description

**Requirements:**
- Not already registered
- Balance >= `creatorRegistrationFee`

**Effects:**
- Burns `creatorRegistrationFee` FAM tokens
- Creates creator profile
- Emits `CreatorRegistered` event

#### `getCreatorInfo(address creator)`
Get detailed creator information.

**Returns:**
- `name`: Creator name
- `bio`: Creator bio
- `isActive`: Registration status
- `keysSupply`: Total keys in circulation
- `totalVolume`: Trading volume
- `registrationTime`: Unix timestamp
- `keysSoldDirectly`: Keys sold by creator directly

### Keys Trading

#### `buyKeys(address creator, uint256 amount)`
Buy keys directly from creator using FAM tokens.

**Parameters:**
- `creator`: Creator address
- `amount`: Number of keys to buy

**Requirements:**
- Creator exists and active
- Creator hasn't exceeded direct sales limit
- Sufficient FAM balance

**Effects:**
- Transfers FAM tokens to contract
- Mints keys to buyer
- Distributes fees
- Updates creator stats

#### `sellKeys(address creator, uint256 amount)`
Sell keys back to platform for FAM tokens.

**Parameters:**
- `creator`: Creator address
- `amount`: Number of keys to sell

**Requirements:**
- Creator exists
- Sufficient key balance
- Keys available in supply

**Effects:**
- Burns keys from seller
- Returns FAM tokens minus fees
- Distributes fees to platform and creator

#### `getBuyPrice(address creator, uint256 amount)`
Calculate price for buying keys (before fees).

**Returns:** Price in FAM tokens (18 decimals)

#### `getSellPrice(address creator, uint256 amount)`
Calculate price for selling keys (before fees).

**Returns:** Price in FAM tokens (18 decimals)

#### `getBuyPriceAfterFee(address creator, uint256 amount)`
Get total cost including all fees.

#### `getSellPriceAfterFee(address creator, uint256 amount)`
Get net proceeds after all fees.

### ERC20 Functions

#### `transfer(address to, uint256 amount)`
Transfer with 5% tax (3% burn, 2% to platform).

#### `transferFrom(address from, address to, uint256 amount)`
Transfer with tax (requires approval).

#### `balanceOf(address account)`
Get FAM token balance.

#### `totalSupply()`
Get total FAM supply.

### View Functions

#### `getKeysBalance(address user, address creator)`
Get user's key balance for specific creator.

#### `getTotalCreators()`
Get total number of registered creators.

#### `getKeysRemainingForDirectSale(address creator)`
Get remaining keys creator can sell directly.

### Admin Functions

#### `updateMaxCreatorKeys(uint256 _newMax)`
Update maximum keys per creator (owner only).

#### `updateRegistrationFee(uint256 _newFee)`
Update creator registration fee (owner only).

#### `setStakingVault(address _newVault)`
Update staking vault address (owner only).

#### `withdrawPlatformFees()`
Withdraw accumulated fees to staking vault (owner only).

#### `setTaxExempt(address _address, bool _exempt)`
Exempt address from transfer taxes (owner only).

#### `deactivateCreator(address creator)`
Deactivate creator account (owner only).

#### `burnPlatformFees(uint256 amount)`
Emergency burn of platform fees (owner only).

## 🔧 Bonding Curve

### Formula
```
Price = (supply²) / 16000 FAM
```

### Examples
| Keys Supply | Buy Price/Key | Sell Price/Key |
|-------------|----------------|----------------|
| 0 → 1 | 0.0000625 FAM | - |
| 100 → 101 | 0.625 FAM | 0.61875 FAM |
| 1000 → 1001 | 62.5 FAM | 61.875 FAM |

## 🎭 Key Scarcity System

### Direct Sales Limit
- Creators can sell maximum `maxCreatorKeys` (default: 1,000)
- After limit reached: "Creator reached direct sales limit. Buy from other fans!"
- Forces P2P secondary market

### P2P Trading
- Unlimited trading between fans
- Platform and creator still earn fees
- No supply limits on secondary market

## 📊 Events

### `CreatorRegistered(address creator, string name, uint256 fee)`
Emitted when creator registers.

### `KeysBought(address buyer, address creator, uint256 amount, uint256 price, uint256 platformFee, uint256 creatorFee)`
Emitted when keys are purchased.

### `KeysSold(address seller, address creator, uint256 amount, uint256 price, uint256 platformFee, uint256 creatorFee)`
Emitted when keys are sold.

### `TaxApplied(address from, uint256 amount, uint256 burned, uint256 vaulted)`
Emitted on taxed transfers.

### `MaxCreatorKeysUpdated(uint256 oldMax, uint256 newMax)`
Emitted when max keys updated.

### `RegistrationFeeUpdated(uint256 oldFee, uint256 newFee)`
Emitted when registration fee updated.

## 🛡️ Security Features

- **ReentrancyGuard**: Prevents reentrancy attacks
- **Input Validation**: All parameters validated
- **Access Control**: Owner-only admin functions
- **Safe Transfers**: Uses OpenZeppelin ERC20

## 🧪 Testing

### Key Test Cases
1. Creator registration and fee burning
2. Key purchasing with fee distribution
3. Key selling with P2P trading
4. Scarcity limits enforcement
5. Admin parameter updates
6. Tax application on transfers

### Test Networks
- Sepolia (Ethereum testnet)
- Base Sepolia (recommended for low fees)

## 📈 Usage Example

```javascript
// 1. Deploy contract
const stakingVault = "0x...";
const token = await FamToken.deploy(stakingVault);

// 2. Creator registers (burns 1,000 FAM)
await token.registerCreator("Alice", "Musician");

// 3. Fan buys keys
const cost = await token.getBuyPriceAfterFee(aliceAddress, 10);
await token.buyKeys(aliceAddress, 10, {value: cost});

// 4. Fan sells keys
const proceeds = await token.getSellPriceAfterFee(aliceAddress, 5);
await token.sellKeys(aliceAddress, 5);

// 5. Check balances
const keysOwned = await token.getKeysBalance(userAddress, aliceAddress);
const famBalance = await token.balanceOf(userAddress);
```

## 🔗 Dependencies

- **OpenZeppelin Contracts**: ERC20, Ownable, ReentrancyGuard
- **Solidity Version**: ^0.8.20
- **Network**: Any EVM-compatible chain

## 📝 License

MIT License - see contract header for details.

## 🤝 Contributing

This contract implements a creator economy with sustainable tokenomics. For improvements or bug reports, please review the code carefully.

---

*Built for Fam.app - Empowering creators through decentralized fan engagement*
