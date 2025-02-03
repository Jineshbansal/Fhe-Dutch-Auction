# Single-Price Auction for Tokens with Sealed Bids using Zama's fhEVM 


## Overview
In this contract we implemented a Single-Price Sealed-Bid Auction using Solidity and FHEVM, ensuring bid confidentiality while settling the auction at a uniform price (the lowest price required to fulfill all token sales). 

## System design

## Key Design Decisions in our Auction Contract 

1. Single Bid Per Address

Each participant can submit only one bid. If they wish to change it, they must modify their existing bid.

2. Bid Modification Allowed

Users can update their bid before the auction ends, ensuring they can adjust based on market conditions.

3. Auction Duration Control

The auction creator decides the duration, offering flexibility in setting the bidding window.

4. Handling Equal Lowest Bids

If multiple bidders have the same lowest price at the cut-off, tokens are distributed proportionally based on the quantity they bid for.

5. Funds Requirement at Bidding Time

Participants must provide funds upfront when placing a bid. This ensures only serious bidders participate, reducing spam and fraudulent bidding



## Usage

### Pre Requisites

Install [pnpm](https://pnpm.io/installation)

Before being able to run any command, you need to create a `.env` file and set a BIP-39 compatible mnemonic as the `MNEMONIC`
environment variable. You can follow the example in `.env.example` or start with the following command:

```sh
cp .env.example .env
```

If you don't already have a mnemonic, you can use this [website](https://iancoleman.io/bip39/) to generate one. An alternative, if you have [foundry](https://book.getfoundry.sh/getting-started/installation) installed is to use the `cast wallet new-mnemonic` command.

Then, install all needed dependencies - please **_make sure to use Node v20_** or more recent:

```sh
pnpm install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
pnpm compile
```

### TypeChain

Compile the smart contracts and generate TypeChain bindings:

```sh
pnpm typechain
```

### Test

Run the tests with Hardhat - this will run the tests on a local hardhat node in mocked mode (i.e the FHE operations and decryptions will be simulated by default):

```sh
pnpm test
```

### Lint Solidity

Lint the Solidity code:

```sh
pnpm lint:sol
```

### Lint TypeScript

Lint the TypeScript code:

```sh
pnpm lint:ts
```


### Clean

Delete the smart contract artifacts, the coverage reports and the Hardhat cache:

```sh
pnpm clean
```

### VSCode Integration

This template is IDE agnostic, but for the best user experience, you may want to use it in VSCode alongside Nomic
Foundation's [Solidity extension](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity).



### Syntax Highlighting

If you use VSCode, you can get Solidity syntax highlighting with the
[hardhat-solidity](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity) extension.
