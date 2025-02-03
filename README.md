# Single-Price Auction for Tokens with Sealed Bids using Zama's fhEVM 


## Overview
We implemented a **Single-Price Sealed-Bid Auction** using **Solidity** and **FHEVM**, ensuring **bid confidentiality** while determining a **uniform clearing price**—the lowest bid price required to fulfill all token sales. The auctioned tokens are **ERC20 tokens**, whereas the bidding tokens are **ConfidentialERC20**, preserving **bidder privacy** throughout the process.


## System Design
<img width="722" alt="Screenshot 2025-02-03 at 6 50 04 PM" src="https://github.com/user-attachments/assets/089d0e98-8c80-4068-af27-3d0d11f18c51" />



## Key Design Decisions in our Auction Contract

1. **Claim-Based Token Distribution**

    Initially, we considered distributing the auction proceeds to bidders within the function `settleAuctionPayments`. However, due to the limit on the number of operations in `Fully Homomorphic Encryption (FHE)`, we shifted to a claim-based system where users must actively call a function to claim their auction tokens. This approach ensures efficiency while maintaining security and fairness in the distribution process.

2. **Single Bid Per Address**

    Each participant can submit only one bid. If they wish to change it, they must modify their existing bid.

3. **Bid Modification Allowed**

    Users can update their bid before the auction ends, ensuring they can adjust based on market conditions.

4. **Auction Duration Control**

    The auction creator decides the duration, offering flexibility in setting the bidding window.

5. **Handling Equal Lowest Bids**

    If multiple bidders have the same lowest price at the cut-off, tokens are distributed proportionally based on the quantity they bid for.

6. **Funds Requirement at Bidding Time**

    Participants must provide funds upfront when placing a bid. This ensures only serious bidders participate, reducing spam and fraudulent bidding.

7. **Handling Insufficient Participation**

    If the auction does not receive any bids or has too few participants, it is considered not fully sold. In such cases, the auction execution will occur at the lowest set price, and any unsold tokens will be returned to the auction owner.


## Functions in blindAuctionERC20.sol
1. **initiateAuction**
    - **Purpose**: Allows users to create a new blind auction where participants can place encrypted bids for ERC20 tokens.
    - **Parameters**:
      - `_auctionTokenAddress`: The address of the ERC20 token being auctioned.
      - `_bidTokenAddress`: The address of the ERC20 token used for bidding.
      - `_auctionTitle`: Name or description of the auction.
      - `_tokensPutOnTheAuction`: Number of tokens available for sale.
      - `_startingtime`: Delay (in seconds) before the auction starts.
      - `_endTime`: Delay (in seconds) before the auction ends.
    - **Key Actions**:
      - Verifies that the auction end time is valid.
      - Ensures the bid token address is legitimate.
      - Creates and stores an auction with unique auctionId.
      - Transfers auction tokens from the creator to the contract.
      - Marks the auction as active.

2. **placeEncryptedBid**
    - **Purpose**: Allows bidders to submit encrypted bids for an auction.
    - **Parameters**:
      - `_auctionId`: The ID of the auction being bid on.
      - `_tokenRate`: Encrypted bid rate per token.
      - `_tokenRateproof`: Proof of the bid rate encryption.
      - `_tokenCount`: Encrypted number of tokens the bidder wants.
      - `_tokenCountproof`: Proof of token count encryption.
    - **Key Actions**:
      - Ensures bidding is allowed during the auction timeframe.
      - Converts encrypted bid values into euint64 format.
      - Verifies that the bidder has not already placed a bid.
      - Stores the bid securely in encrypted form.
      - Transfers encrypted funds from the bidder to the contract.

3. **decryptAuctionBids**
    - **Purpose**: Decrypts all bids for an auction after it ends.
    - **Parameters**:
      - `_auctionId`: The ID of the auction.
    - **Key Actions**:
      - Ensures that only the auction owner can decrypt bids.
      - Verifies the auction has not already been decrypted.
      - Requests decryption for all bids using the FHE Gateway.
      - Stores the decrypted bids for further processing.

4. **settleAuctionPayments**
    - **Purpose**: Determines the final clearing price after the auction ends.
    - **Parameters**:
      - `_auctionId`: The ID of the auction.
    - **Key Actions**:
      - Verifies that the auction has ended.
      - Ensures that all bids have been decrypted.
      - Sorts bids in descending order based on bid price.
      - Finds the price at which all available tokens are allocated.
      - Transfers funds to the auction owner.
      - Returns unsold tokens to the auction owner.

5. **claimAuctionTokens**
    - **Purpose**: Allows bidders to claim their tokens or refunds after the auction ends.
    - **Parameters**:
      - `_auctionId`: The ID of the auction.
    - **Key Actions**:
      - Ensures that the auction has ended.
      - Checks each bid and processes refunds based on final price:
         - If bid > final price → Refund excess amount & transfer tokens.
         - If bid == final price → Allocate tokens proportionally.
         - If bid < final price → Refund full bid amount.
      - Marks the bid as claimed.

6. **increaseBidAmount**
    - **Purpose**: Allows a bidder to increase their bid in an active auction.
    - **Parameters**:
      - `_auctionId`: ID of the auction.
      - `_tokenRate`: New encrypted bid rate per token.
      - `_tokenRateproof`: Proof of new bid rate encryption.
      - `_tokenCount`: New encrypted token quantity.
      - `_tokenCountproof`: Proof of new token count encryption.
    - **Key Actions**:
      - Ensures the auction is still active.
      - Updates the bid with new encrypted values.
      - Transfers additional bid amount from the bidder to the contract.

7. **decreaseBidAmount**
    - **Purpose**: Allows a bidder to decrease their bid in an active auction.
    - **Parameters**:
      - `_auctionId`: ID of the auction.
      - `_tokenRate`: New encrypted bid rate per token.
      - `_tokenRateproof`: Proof of new bid rate encryption.
      - `_tokenCount`: New encrypted token quantity.
      - `_tokenCountproof`: Proof of new token count encryption.
    - **Key Actions**:
      - Ensures the auction is still active.
      - Updates the bid with new encrypted values.
      - Refunds excess bid amount to the bidder.



## Getting Started

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
