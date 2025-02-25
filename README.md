# CL8Y token

## About

CL8Y (Ceramic Liberty) is a deflationary token designed to sustainably fund open-source blockchain development. Created by Ceramic, a blockchain developer with extensive experience since 2018, CL8Y implements an innovative tokenomic model that aligns the interests of open-source projects, developers, and token holders.

### Core Features

- **Total Supply**: 3,000,000 CL8Y tokens
- **Launch Date**: March 1, 2025
- **Network**: Binance Smart Chain (BSC)
- **Trading Mechanics**: Zero buy tax, declining sell tax structure
- **Smart Contract**: Advanced security features with OpenZeppelin standards

### Tokenomics

- **Initial Sell Tax**: 30% (burned)
- **Tax Reduction Schedule**:
  - 10% at 24 hours
  - 1% at 7 days
  - 0.25% at $10M market cap
- **Max Wallet**: Initially 1,000 tokens, 10,000 after 1 hour, unlimited after 24 hours
- **Trading Restrictions**: Anti-bot measures and fair launch protections

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

- ERC20 standard with burn functionality
- Permit extension for gasless approvals
- Dynamic tax and wallet limit adjustments
- Automated liquidity pair creation
- Owner controls with security timeouts

## License

License: GPL-3.0

## build

forge build --via-ir

## deployment

Key variables are set in the script, and should be updated correctly for the network.
forge script script/DeployCL8Y.s.sol:DeployCL8Y --broadcast --verify -vvv --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY -i 1 --sender $DEPLOYER_ADDRESS
