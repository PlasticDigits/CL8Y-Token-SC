# CL8Y token

## About

CL8Y (Ceramic Liberty) is a deflationary token designed to sustainably fund open-source blockchain development. Created by Ceramic, a blockchain developer with extensive experience since 2018, CL8Y implements an innovative tokenomic model that aligns the interests of open-source projects, developers, and token holders.

AccessManager BSC: `0x5823a01A5372B779cB091e47DBBb176F2831b4c7`
DatastoreSetAddress BSC: `0x8a18c91387149806BE5F7c1ebc6fE99e12d183dA`
GuardERC20 BSC: `0x417580DF7eE35FFA6286255b55B456c992657fB9`
BlacklistReceiverOnly BSC: `0x513375eb5bE203Ad4BA442Cc02C4f36d89932659`
BlacklistSenderOnly BSC: `0x3009E9de998E62D75f8342109270c9F919F3a885`
RateLimiting BSC: `0xeD380ED75890ee6458Ba2b0070c68b61c8Ceb41B`
CL8Y Address BSC: `0x8F452a1fdd388A45e1080992eFF051b4dd9048d2`

### AccessManager Roles

1: Guard Module Manager
2: Blacklist Manager

### Core Features

- **Total Supply**: 3,000,000 CL8Y tokens
- **Launch Date**: March 1, 2025
- **Network**: Binance Smart Chain (BSC)
- **Trading Mechanics**: Zero fees, no taxes, no restrictions by default
- **Smart Contract**: Simplified architecture with modular security system

### Architecture (v2)

CL8Y v2 features a revolutionary **modular design** that separates core token functionality from security features:

- **Simplified Core Contract**: Clean, minimal ERC20 implementation with burn functionality
- **GuardERC20 System**: Modular security framework allowing dynamic addition/removal of protection modules
- **Optional Guard Modules**:
  - Blacklist protection
  - Rate limiting
  - Custom restrictions as needed
- **No Built-in Restrictions**: Clean token by default - modules only added when specifically needed
- **Dynamic Management**: Security features can be modified without affecting the core token

### Tokenomics

- **No Taxes or Fees**: Pure token transfers with no built-in friction
- **No Wallet Limits**: Unlimited holding and trading capacity
- **No Trading Restrictions**: Open market participation from launch
- **Burn Functionality**: Deflationary mechanism through token burning
- **Modular Protection**: Optional security features via guard modules when needed

### Purpose & Vision

CL8Y serves as a sustainable funding mechanism for open-source blockchain development. Projects utilizing Ceramic's open-source technologies can support ongoing development through automated CL8Y purchases for burns and liquidity provision. This creates:

1. Sustainable funding for public good development
2. Constant buy pressure benefiting holders
3. Increasing scarcity through systematic burns
4. Fair value distribution with no presales or private allocations

### Community & Social

- Telegram: t.me/ceramicliberty
- Twitter: x.com/ceramictoken

### Technical Implementation

The smart contract implements:

- **Core Token (CL8Y_v2)**:

  - Standard ERC20 with burn functionality
  - Integration with GuardERC20 system
  - Minimal, auditable codebase (31 lines)

- **GuardERC20 System**:

  - Modular architecture for security features
  - Dynamic module management via AccessManager
  - Extensible design for future functionality
  - Optional protection modules (blacklist, rate limiting, etc.)

- **DatastoreSetAddress**:
  - Efficient storage for modular configurations
  - Support for multiple address sets per module

## License

License: GPL-3.0

## build

forge build --via-ir

## deployment

Key variables are set in the script, and should be updated correctly for the network.
forge script script/DeployCL8Y_v2.s.sol:DeployCL8Y_v2 --broadcast --verify --verifier etherscan -vvv --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY -i 1 --sender $DEPLOYER_ADDRESS
