// SPDX-License-Identifier: BSD-3-Clause-Clear

// BlindAuctionERC20 Contract
// This smart contract implements a confidential blind auction using Fully Homomorphic Encryption (FHE).
// Participants can place encrypted bids on ERC20 tokens, ensuring privacy and security throughout the auction process.
// The contract supports bid encryption, decryption, fair price determination, and secure fund transfers.
// Built on the Zama FHEVM framework, it enables confidential computations on encrypted values.
// Developed for use on Sepolia testnet with FHE-enabled ERC20 tokens.
pragma solidity ^0.8.24;


import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract BlindAuctionERC20 is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    address public owner;
    uint256 public auctionCount = 1;
    constructor() {
        owner = msg.sender;
    }

    struct Auction {
        address auctionTokenAddress; // Address of the token being auctioned
        address bidtokenAddress; // Address of the token used for bidding
        string auctionTitle; // Title or description of the auction
        uint256 auctionId; // Unique identifier for the auction
        address auctionOwner; // Address of the auction creator
        string tokenName; // Name of the token being auctioned
        uint64 tokensPutOnTheAuction; // Total number of tokens available in the auction
        uint256 startTime; // Timestamp when the auction starts
        uint256 endTime; // Timestamp when the auction ends
        bool isActive; // Indicates if the auction is currently active
        bool isDecrypted; // Indicates if auction details are decrypted
    }

    struct Bid {
        address bidId; // Unique identifier for the bid (could be bidder's address)
        uint256 auctionId; // ID of the auction this bid belongs to
        euint64 perTokenRate; // Encrypted rate per token in bid
        euint64 tokenAsked; // Encrypted number of tokens requested in bid
        bool isClaimed; // Whether the bid has been claimed or settled
    }

    struct BidPlaintext {
        address bidId; // Unique identifier for the bid (could be bidder's address)
        uint256 auctionId; // ID of the auction this bid belongs to
        uint64 perTokenRate; // Rate per token in bid (unencrypted version)
        uint64 tokenAsked; // Number of tokens requested in bid (unencrypted version)
        bool isClaimed; // Whether the bid has been claimed or settled
    }

    mapping(address => Auction[]) public myAuctions;
    // Stores all auctions created by a specific user (auction owner address → array of auctions).

    mapping(uint256 => Auction) public auctions;
    // Maps an auction ID to its corresponding auction details.

    mapping(uint256 => Bid[]) private auctionBids;
    // Stores all bids for a specific auction (auction ID → array of encrypted bids).

    mapping(uint256 => uint64) public auctionBidsEdgeWinner;
    // Stores the per-token rate of the "edge winner" bid (auction ID → winning per-token bid rate).
    // The edge winner is typically the last winning bid that sets the final price.

    mapping(uint256 => uint64) public auctionAmountLeftForEdgeWinner;
    // Stores the remaining token amount for the edge winner bid after partial fulfillment.

    mapping(uint256 => uint64) public auctionFinalPrice;
    // Stores the final price per token determined at auction completion.

    mapping(uint256 => BidPlaintext[]) public auctionPlaintextBids;
    // Stores decrypted bid details after auction ends (auction ID → array of plaintext bids).

    mapping(address => Bid[]) myBids;
    // Stores all bids placed by a specific user (bidder address → array of their bids).

    // Create a new Auction
    function initiateAuction(
        address _auctionTokenAddress, // Address of the token being auctioned
        address _bidTokenAddress, // Address of the token used for bidding
        string calldata _auctionTitle, // Title or name of the auction
        uint64 _tokensPutOnTheAuction, // Total number of tokens available in the auction
        uint256 _startingtime, // Time delay before auction starts (relative to block time)
        uint256 _endTime // Time delay before auction ends (relative to block time)
    ) public {
        // Ensure the auction end time is after the start time
        require(_endTime >= _startingtime,"Invalid time");

        // Verify the bid token has a valid supply (though checking >= 0 is unnecessary)
        require(ConfidentialERC20(_bidTokenAddress).totalSupply() >= 0, "Invalid BidToken address");

        // Create a new auction with the provided details
        Auction memory newAuction = Auction({
            auctionTokenAddress: _auctionTokenAddress,
            bidtokenAddress: _bidTokenAddress,
            auctionTitle: _auctionTitle,
            auctionOwner: msg.sender, // The auction creator
            auctionId: auctionCount, // Unique auction identifier
            tokenName: "auctionToken", // Default name for auctioned tokens
            tokensPutOnTheAuction: _tokensPutOnTheAuction, // Total tokens available in auction
            startTime: block.timestamp + _startingtime, // Start time of auction
            endTime: block.timestamp + _endTime, // End time of auction
            isActive: true, // Auction is active upon creation
            isDecrypted: false // Auction bid details are initially encrypted
        });

        // Store the auction details for the owner and globally
        myAuctions[msg.sender].push(newAuction);
        auctions[auctionCount] = newAuction;

        // Transfer auction tokens from the creator to the contract for holding
        require(
            IERC20(_auctionTokenAddress).transferFrom(msg.sender, address(this), _tokensPutOnTheAuction),
            "Transfer failed"
        );

        // Increment auction count to ensure unique auction IDs
        auctionCount++;
    }

    // Create an encrypted bid
    function placeEncryptedBid(
        uint256 _auctionId, // ID of the auction being bid on
        einput _tokenRate, // Encrypted rate per token
        bytes calldata _tokenRateproof, // Proof for token rate
        einput _tokenCount, // Encrypted count of tokens being bid on
        bytes calldata _tokenCountproof // Proof for token count
    ) public {

        // Ensure bidding is within the allowed timeframe
        require(block.timestamp >= auctions[_auctionId].startTime && block.timestamp <= auctions[_auctionId].endTime, "Auction time error");

        uint256 auctionId = _auctionId; // Store auction ID locally
        address bidderId = msg.sender; // Store bidder's address

        // Convert encrypted inputs into encrypted uint64 values
        euint64 tokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 tokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);

        // Authorize encrypted values for further computation
        TFHE.allowThis(tokenRate);
        TFHE.allowThis(tokenAsked);

        // Create a new bid
        Bid memory newBid = Bid({
            auctionId: auctionId,
            bidId: bidderId,
            perTokenRate: tokenRate, // Rate per token (encrypted)
            tokenAsked: tokenAsked, // Number of tokens requested (encrypted)
            isClaimed: false // Initial state of the bid (not claimed)
        });

        // Authorize encrypted fields of the new bid
        TFHE.allowThis(newBid.perTokenRate);
        TFHE.allowThis(newBid.tokenAsked);

        // Ensure the bidder has not already placed a bid for this auction
        for (uint i = 0; i < myBids[bidderId].length; i++) {
            if (myBids[bidderId][i].auctionId == auctionId) {
                revert("Bid Exists");
            }
        }

        // Store the bid in the bidder's records
        myBids[bidderId].push(newBid);

        // Authorize newly added bid in the bidder's list
        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].perTokenRate);
        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].tokenAsked);

        // Store the bid in the auction's bid list
        auctionBids[auctionId].push(newBid);

        // Authorize newly added bid in the auction's bid list
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].perTokenRate);
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].tokenAsked);

        // Compute the total amount to be transferred (tokenRate * tokenAsked)
        euint64 tokenSubmit = TFHE.mul(tokenAsked, tokenRate);
        TFHE.allowThis(tokenSubmit);

        // Allow transient use of encrypted bid amount in the bidding token contract
        TFHE.allowTransient(tokenSubmit, auctions[auctionId].bidtokenAddress);

        // Transfer the calculated bid amount from the bidder to the contract
        require(
            ConfidentialERC20(auctions[auctionId].bidtokenAddress).transferFrom(msg.sender, address(this), tokenSubmit),
            "Transfer failed"
        );
    }
    // Requests decryption for a bid's per-token rate and token count
    function requestBidDecryption(
        address bidId, // Address of the bidder
        uint256 auctionId, // ID of the auction
        euint64 perTokenRate, // Encrypted per-token bid rate
        euint64 tokensPutOnTheAuction // Encrypted token count
    ) internal {
        // Create an array to store encrypted values as uint256
        uint256[] memory cts = new uint256[](2);
        cts[0] = Gateway.toUint256(perTokenRate); // Convert encrypted per-token rate to uint256
        cts[1] = Gateway.toUint256(tokensPutOnTheAuction); // Convert encrypted token count to uint256

        // Request decryption through the gateway
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.handleDecryptionCallback.selector, // Callback function to handle the decrypted data
            0, // No additional fee
            block.timestamp + 100, // Decryption deadline
            false // Not an urgent request
        );

        // Store the request ID and its associated parameters
        addParamsAddress(requestID, bidId);
        addParamsUint256(requestID, auctionId);
    }

    // Callback function to receive decrypted bid data
    function handleDecryptionCallback(
        uint256 requestID, // The ID of the decryption request
        uint64 perTokenRate, // Decrypted per-token rate
        uint64 tokensPutOnTheAuction // Decrypted token count
    ) public onlyGateway {
        // Retrieve stored parameters using requestID
        uint256[] memory params = getParamsUint256(requestID);
        address[] memory paramsAddress = getParamsAddress(requestID);

        // Extract bid and auction details
        address bidId = paramsAddress[0];
        uint256 auctionId = params[0];

        // Store the decrypted bid information in the plaintext bid mapping
        auctionPlaintextBids[auctionId].push(BidPlaintext(bidId, auctionId, perTokenRate, tokensPutOnTheAuction, false));
    }

    // Function to decrypt all bids in an auction
    function decryptAuctionBids(uint256 _auctionId) public {
        // Ensure that only the auction owner can decrypt bids
        require(msg.sender == auctions[_auctionId].auctionOwner, "Not Owner");

        // Ensure the auction has not already been decrypted
        require(auctions[_auctionId].isDecrypted == false, "Decrypted");

        // Mark the auction as decrypted
        auctions[_auctionId].isDecrypted = true;

        // Retrieve all bids placed in the auction
        Bid[] memory totalBids = auctionBids[_auctionId];

        // Iterate through each bid and request decryption
        for (uint64 i = 0; i < totalBids.length; i++) {
            requestBidDecryption(
                totalBids[i].bidId,
                totalBids[i].auctionId,
                totalBids[i].perTokenRate,
                totalBids[i].tokenAsked
            );
        }
    }

    // Function to calculate the final clearing price of an auction
    function settleAuctionPayments(uint256 _auctionId) public {
        uint256 auctionId = _auctionId;

        // Ensure the auction is active and has ended
        require(auctions[auctionId].isActive, "Inactive");
        require(block.timestamp > auctions[auctionId].endTime, "Not ended");

        // Ensure all bids have been decrypted before proceeding
        require(
            auctionPlaintextBids[_auctionId].length == auctionBids[_auctionId].length,
            "Bids not revealed"
        );

        // Retrieve all decrypted bids
        BidPlaintext[] memory totalBids = auctionPlaintextBids[_auctionId];

        // Sort bids in descending order based on perTokenRate (bubble sort)
        for (uint i = 0; i < totalBids.length; i++) {
            for (uint j = 0; j < totalBids.length - i - 1; j++) {
                if (totalBids[j].perTokenRate < totalBids[j + 1].perTokenRate) {
                    BidPlaintext memory temp = totalBids[j];
                    totalBids[j] = totalBids[j + 1];
                    totalBids[j + 1] = temp;
                }
            }
        }

        uint64 totalTokens = auctions[_auctionId].tokensPutOnTheAuction; // Total tokens available for sale
        uint64 tempTotalTokens = totalTokens; // Track remaining tokens

        uint64 finalPrice = 0; // Variable to store the final auction price

        // Determine the final clearing price based on bid order
        for (uint64 i = 0; i < totalBids.length; i++) {
            if (tempTotalTokens > 0) {
                if (totalBids[i].perTokenRate == 0) {
                    continue; // Skip bids with zero price
                }

                uint64 bidCount = totalBids[i].tokenAsked;
                if (bidCount > tempTotalTokens) {
                    bidCount = tempTotalTokens; // Allocate only available tokens
                }
                tempTotalTokens -= bidCount; // Reduce remaining token supply
                finalPrice = totalBids[i].perTokenRate; // Update final price
            } else {
                break;
            }
        }

        uint64 sellTokensWithProfit = 0; // Track tokens sold at a profit

        // Calculate the edge winner bid count and tokens sold with profit
        for (uint64 i = 0; i < totalBids.length; i++) {
            if (totalBids[i].perTokenRate > finalPrice) {
                sellTokensWithProfit += totalBids[i].tokenAsked; // Tokens sold at a premium
            }
            if (finalPrice == totalBids[i].perTokenRate) {
                auctionBidsEdgeWinner[_auctionId] += totalBids[i].tokenAsked; // Edge winners at the final price
            }
        }

        // Calculate remaining tokens left for edge winners
        if (tempTotalTokens > 0) {
            auctionAmountLeftForEdgeWinner[_auctionId] = (totalTokens - tempTotalTokens) - sellTokensWithProfit;
        } else {
            auctionAmountLeftForEdgeWinner[_auctionId] = totalTokens - sellTokensWithProfit;
        }

        // Mark auction as inactive and set the final price
        auctions[_auctionId].isActive = false;
        auctionFinalPrice[_auctionId] = finalPrice;

        // Calculate the total value of successfully sold tokens
        uint64 sellTokens = totalTokens - tempTotalTokens;
        euint64 toTransfer = TFHE.asEuint64(sellTokens * finalPrice);

        // Approve the transfer of the total bid amount to the auction owner
        TFHE.allowTransient(toTransfer, auctions[_auctionId].bidtokenAddress);
        require(
            ConfidentialERC20(auctions[_auctionId].bidtokenAddress).transfer(
                auctions[_auctionId].auctionOwner,
                toTransfer
            ),
            "Transfer failed"
        );

        // Transfer any remaining unsold auction tokens back to the owner
        require(
            IERC20(auctions[_auctionId].auctionTokenAddress).transfer(
                auctions[_auctionId].auctionOwner,
                tempTotalTokens
            ),
            "Transfer failed"
        );
    }
    // Function for bidders to reclaim their tokens or refunds after an auction ends
    function claimAuctionTokens(uint256 _auctionId) public {
        require(auctions[_auctionId].isActive == false, "Still active"); // Ensure auction is finished

        uint256 auctionId = _auctionId;
        uint64 finalPrice = auctionFinalPrice[_auctionId]; // Retrieve the final auction price
        BidPlaintext[] memory totalBids = auctionPlaintextBids[_auctionId]; // Get all decrypted bids

        // Loop through all bids to find the ones made by the caller
        for (uint i = 0; i < totalBids.length; i++) {
            if (totalBids[i].bidId == msg.sender) {
                // If the bid belongs to the caller
                require(totalBids[i].isClaimed == false, "Claimed"); // Ensure tokens have not been claimed

                if (totalBids[i].perTokenRate > finalPrice) {
                    // Case 1: Bid was higher than the final price - Refund the difference & transfer tokens
                    uint64 bidAmount = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    uint64 finalAmount = totalBids[i].tokenAsked * finalPrice;
                    euint64 refundAmount = TFHE.asEuint64(bidAmount - finalAmount); // Compute refund amount
                    TFHE.allowTransient(refundAmount, auctions[auctionId].bidtokenAddress);

                    require(
                        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(
                            totalBids[i].bidId,
                            refundAmount
                        ),
                        "transfer failed"
                    );

                    require(
                        IERC20(auctions[auctionId].auctionTokenAddress).transfer(
                            totalBids[i].bidId,
                            totalBids[i].tokenAsked
                        ),
                        "transfer failed"
                    );
                } else if (totalBids[i].perTokenRate == finalPrice) {
                    // Case 2: Bid was exactly the final price - Partial refund based on edge winner allocation
                    uint64 tokenGet = (totalBids[i].tokenAsked * auctionAmountLeftForEdgeWinner[_auctionId]) /
                        auctionBidsEdgeWinner[_auctionId];

                    uint64 bidAmount = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    uint64 finalAmount = tokenGet * finalPrice;
                    euint64 refundAmount = TFHE.asEuint64(bidAmount - finalAmount);
                    TFHE.allowTransient(refundAmount, auctions[auctionId].bidtokenAddress);

                    require(
                        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(
                            totalBids[i].bidId,
                            refundAmount
                        ),
                        "transfer failed"
                    );

                    require(
                        IERC20(auctions[auctionId].auctionTokenAddress).transfer(totalBids[i].bidId, tokenGet),
                        "transfer failed"
                    );
                } else {
                    // Case 3: Bid was lower than final price - Full refund
                    uint64 refundAmount = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    euint64 refundAmountEncrypted = TFHE.asEuint64(refundAmount);
                    TFHE.allowTransient(refundAmountEncrypted, auctions[auctionId].bidtokenAddress);

                    require(
                        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(
                            totalBids[i].bidId,
                            refundAmountEncrypted
                        ),
                        "transfer failed"
                    );
                }

                totalBids[i].isClaimed = true; // Mark the bid as claimed
            }
        }
    }
    // Function to allow a bidder to update their bid in an active auction
    function increaseBidAmount(
        uint256 _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        // Ensure the auction is still active
        require(auctions[_auctionId].isActive == true);

        uint256 auctionId = _auctionId;

        // Convert encrypted token rate and token count into usable euint64 values
        euint64 updateTokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 updateTokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);

        address bidderId = msg.sender;

        // Allow the updated token rate and token count
        TFHE.allowThis(updateTokenRate);
        TFHE.allowThis(updateTokenAsked);

        // Iterate through the bidder's own bids
        for (uint i = 0; i < myBids[bidderId].length; i++) {
            // If this is the bid corresponding to the auctionId
            if (myBids[bidderId][i].auctionId == auctionId) {
                // Calculate the previous and updated total value of the bid (perTokenRate * tokenAsked)
                euint64 previousBidAmount = TFHE.mul(myBids[bidderId][i].perTokenRate, myBids[bidderId][i].tokenAsked);
                TFHE.allowThis(previousBidAmount);

                euint64 updatedBidAmount = TFHE.mul(updateTokenRate, updateTokenAsked);
                TFHE.allowThis(updatedBidAmount);

                // Update the bid details
                myBids[bidderId][i].perTokenRate = updateTokenRate;
                myBids[bidderId][i].tokenAsked = updateTokenAsked;

                // Allow the new values
                TFHE.allowThis(myBids[bidderId][i].perTokenRate);
                TFHE.allowThis(myBids[bidderId][i].tokenAsked);

                // Calculate the difference in the bid amounts (updated - previous)
                euint64 bidDifference = TFHE.sub(updatedBidAmount, previousBidAmount);
                TFHE.allowThis(bidDifference);

                // Allow the transient bid difference to be transferred
                TFHE.allowTransient(bidDifference, auctions[auctionId].bidtokenAddress);

                // Transfer the bid difference (additional tokens required) from the bidder to the contract
                require(
                    ConfidentialERC20(auctions[auctionId].bidtokenAddress).transferFrom(
                        msg.sender,
                        address(this),
                        bidDifference
                    ),
                    "Transfer failed"
                );
            }
        }

        // Update the bid details in the global auctionBids array
        for (uint i = 0; i < auctionBids[_auctionId].length; i++) {
            // If the bid belongs to the caller
            if (auctionBids[_auctionId][i].bidId == msg.sender) {
                // Update the perTokenRate and tokenAsked for the global auctionBids array
                auctionBids[auctionId][i].perTokenRate = updateTokenRate;
                auctionBids[auctionId][i].tokenAsked = updateTokenAsked;

                // Allow the updated values for validation
                TFHE.allowThis(auctionBids[auctionId][i].perTokenRate);
                TFHE.allowThis(auctionBids[auctionId][i].tokenAsked);
            }
        }
    }
    // Function to allow a bidder to decrease their bid in an active auction
    function decreaseBidAmount(
        uint256 _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        // Ensure the auction is still active
        require(auctions[_auctionId].isActive == true);

        uint256 auctionId = _auctionId;

        // Decrypt the updated token rate and token count
        euint64 updateTokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 updateTokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);

        address bidderId = msg.sender;

        // Allow the updated token rate and token count for further use
        TFHE.allowThis(updateTokenRate);
        TFHE.allowThis(updateTokenAsked);

        // Iterate through the bidder's own bids
        for (uint i = 0; i < myBids[bidderId].length; i++) {
            // If this is the bid corresponding to the auctionId
            if (myBids[bidderId][i].auctionId == auctionId) {
                // Calculate the previous total value of the bid (perTokenRate * tokenAsked)
                euint64 previousBidAmount = TFHE.mul(myBids[bidderId][i].perTokenRate, myBids[bidderId][i].tokenAsked);
                TFHE.allowThis(previousBidAmount);

                // Calculate the updated bid amount
                euint64 updatedBidAmount = TFHE.mul(updateTokenRate, updateTokenAsked);
                TFHE.allowThis(updatedBidAmount);

                // Apply the updated values to the bid
                myBids[bidderId][i].perTokenRate = updateTokenRate;
                myBids[bidderId][i].tokenAsked = updateTokenAsked;

                // Allow the updated values
                TFHE.allowThis(myBids[bidderId][i].perTokenRate);
                TFHE.allowThis(myBids[bidderId][i].tokenAsked);

                // Calculate the difference between the old bid and the new bid (refund the excess)
                euint64 refundAmount = TFHE.sub(previousBidAmount, updatedBidAmount);
                TFHE.allowThis(refundAmount);

                // Allow transient use of the refund amount
                TFHE.allowTransient(refundAmount, auctions[auctionId].bidtokenAddress);

                // Transfer the refund amount to the bidder
                require(
                    ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(msg.sender, refundAmount),
                    "Transfer failed"
                );
            }
        }

        // Update the bid details in the global auctionBids array
        for (uint i = 0; i < auctionBids[_auctionId].length; i++) {
            // If the bid belongs to the caller
            if (auctionBids[_auctionId][i].bidId == msg.sender) {
                // Update the perTokenRate and tokenAsked for the global auctionBids array
                auctionBids[auctionId][i].perTokenRate = updateTokenRate;
                auctionBids[auctionId][i].tokenAsked = updateTokenAsked;

                // Allow the updated values for validation
                TFHE.allowThis(auctionBids[auctionId][i].perTokenRate);
                TFHE.allowThis(auctionBids[auctionId][i].tokenAsked);
            }
        }
    }
}
