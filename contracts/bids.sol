// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import { ConfidentialERC20 } from "fhevm-contracts/contracts/token/ERC20/ConfidentialERC20.sol";

contract BlindAuction is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    address public owner;
    uint256 public auctionCount = 1;
    constructor() {
        owner = msg.sender;
    }

    struct Auction {
        address auctionTokenAddress;
        address bidtokenAddress;
        string auctionTitle;
        uint256 auctionId;
        address auctionOwner;
        string tokenName;
        uint64 tokenCount;
        uint64 minCount;
        uint256 startingBidTime;
        uint256 endTime;
        bool isActive;
    }

    struct Bid {
        address bidId;
        uint256 auctionId;
        euint64 perTokenRate;
        euint64 tokenAsked;
    }


    struct BidQuantity {
        euint64 perTokenRate;
        euint64 tokenAsked;
    }

    mapping(address => Auction[]) public MyAuctions; // drop after revealAuction for _auctionId           --
    mapping(uint256 => Auction) public auctions; // drop after revealAuction for _auctionId           --
    mapping(uint256 => Bid[]) public auctionBids; // drop after revealAuction for _auctionId           --
    mapping(uint256 => euint64) public auctionFinalPrice; // drop after revealAuction for _auctionId           --

    Auction[] public allAuctions; // drop after claimLeftAuctionStake for _auctionId   --
    
    mapping(address => Bid[]) myBids; // drop in claimWonAuctionPrize and claimLostAuctionPrize --

    // ------------------

    function getAuctions() public view returns (Auction[] memory) {
        return allAuctions;
    }
    // ------------------

    function createAuction(
        address _auctionTokenAddress,
        address _bidTokenAddress,
        string calldata _auctionTitle,
        uint64 _tokenCount,
        uint256 _startingBid, // may be same as start time
        uint256 _endTime
    ) public {
        Auction memory newAuction = Auction({
            auctionTokenAddress: _auctionTokenAddress,
            bidtokenAddress: _bidTokenAddress,
            auctionTitle: _auctionTitle,
            auctionOwner: msg.sender,
            auctionId: auctionCount,
            tokenName: "auctionToken",
            tokenCount: _tokenCount,
            startingBidTime: block.timestamp + _startingBid,
            minCount: (_tokenCount * 1) / 100,
            endTime: block.timestamp + _endTime,
            isActive: true
        });

        MyAuctions[msg.sender].push(newAuction);
        auctions[auctionCount] = newAuction;
        allAuctions.push(newAuction);

        // Transfer the auction funds
        euint64 encryptedAmount = TFHE.asEuint64(_tokenCount);
        TFHE.allowThis(encryptedAmount);
        TFHE.allowTransient(encryptedAmount, _auctionTokenAddress);
        require(ConfidentialERC20(_auctionTokenAddress).transferFrom(msg.sender, address(this), encryptedAmount));
        auctionCount++;
    }

    function initiateBid(
        uint256 _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        uint256 auctionId = _auctionId;
        euint64 tokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 tokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);
        address bidderId = msg.sender;

        TFHE.allowThis(tokenRate);
        TFHE.allowThis(tokenAsked);
        Bid memory newBid = Bid({
            auctionId: auctionId,
            bidId: bidderId,
            perTokenRate: tokenRate,
            tokenAsked: tokenAsked
        });

        TFHE.allowThis(newBid.perTokenRate);
        TFHE.allowThis(newBid.tokenAsked);

        for (uint i = 0; i < myBids[bidderId].length; i++) {
            if (myBids[bidderId][i].auctionId == auctionId) {
                revert("Bid already exists for this auction");
            }
        }
        myBids[bidderId].push(newBid);

        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].perTokenRate);
        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].tokenAsked);

        auctionBids[auctionId].push(newBid);
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].perTokenRate);
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].tokenAsked);

        euint64 tokenSubmit = TFHE.mul(tokenAsked, tokenRate);
        TFHE.allowThis(tokenSubmit);
        TFHE.allowTransient(tokenSubmit, auctions[auctionId].bidtokenAddress);
        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transferFrom(msg.sender, address(this), tokenSubmit);
    }

    function sortBids(uint256 _auctionId) private returns (BidQuantity[] memory) {
        uint256 auctionId = _auctionId;
        require(auctions[auctionId].isActive == true, "Auction is not active");
        Bid[] memory totalBids = auctionBids[_auctionId];
        BidQuantity[] memory totalBidsQuantity = new BidQuantity[](totalBids.length);
        for (uint64 i = 0; i < totalBids.length; i++) {
            TFHE.allowThis(totalBids[i].perTokenRate);
            TFHE.allowThis(totalBids[i].tokenAsked);
            totalBidsQuantity[i].perTokenRate = totalBids[i].perTokenRate;
            totalBidsQuantity[i].tokenAsked = totalBids[i].tokenAsked;
            TFHE.allowThis(totalBidsQuantity[i].perTokenRate);
            TFHE.allowThis(totalBidsQuantity[i].tokenAsked);

        }

        for (uint i = 0; i < totalBids.length; i++) {
            for (uint j = 0; j < totalBids.length - i - 1; j++) {
                ebool isTrue = TFHE.lt(totalBidsQuantity[j].perTokenRate, totalBidsQuantity[j + 1].perTokenRate);
                TFHE.allowThis(isTrue);
                BidQuantity memory temp = totalBidsQuantity[j];
                TFHE.allowThis(temp.perTokenRate);
                TFHE.allowThis(temp.tokenAsked);

                totalBidsQuantity[j].perTokenRate = TFHE.select(
                    isTrue,
                    totalBidsQuantity[j + 1].perTokenRate,
                    totalBidsQuantity[j].perTokenRate
                );
                totalBidsQuantity[j].tokenAsked = TFHE.select(
                    isTrue,
                    totalBidsQuantity[j + 1].tokenAsked,
                    totalBidsQuantity[j].tokenAsked
                );
                TFHE.allowThis(totalBidsQuantity[j].perTokenRate);
                TFHE.allowThis(totalBidsQuantity[j].tokenAsked);
            }
        }
        return totalBidsQuantity;

    }

    function getFinalPrice(uint256 _auctionId) public  returns (euint64) {

        uint256 auctionId=_auctionId;
        Bid[] memory totalBids = auctionBids[_auctionId];
        BidQuantity[] memory totalBidsQuantity = sortBids(_auctionId);
        euint64 totalTokens = TFHE.asEuint64(auctions[_auctionId].tokenCount);
        TFHE.allowThis(totalTokens);

        euint64 tempTotalTokens = totalTokens;
        TFHE.allowThis(tempTotalTokens);

        euint64 finalPrice = TFHE.asEuint64(0);
        TFHE.allowThis(finalPrice);
        // require(totalBids.length==5,"bids not completed");
        for (uint256 i = 0; i <totalBids.length ; i++) {
            ebool isTrue = TFHE.gt(tempTotalTokens, 0);
            TFHE.allowThis(isTrue);
            euint64 bidCount = TFHE.select(isTrue, totalBidsQuantity[i].tokenAsked, TFHE.asEuint64(0));
            TFHE.allowThis(bidCount);

            bidCount = TFHE.select(
                isTrue,
                TFHE.select(TFHE.gt(bidCount, tempTotalTokens), tempTotalTokens, bidCount),
                bidCount
            );
            TFHE.allowThis(bidCount);
            tempTotalTokens = TFHE.select(isTrue, TFHE.sub(tempTotalTokens, bidCount), tempTotalTokens);
            TFHE.allowThis(tempTotalTokens);
            finalPrice = TFHE.select(isTrue, totalBidsQuantity[i].perTokenRate, finalPrice);
            TFHE.allowThis(finalPrice);
        }
        auctionFinalPrice[_auctionId]=finalPrice;
        TFHE.allowThis(auctionFinalPrice[_auctionId]);
        TFHE.allow(auctionFinalPrice[_auctionId],msg.sender);
        return finalPrice;
    }

    function getFromFinalList(uint256 _auctionId) public view returns (euint64) {
        return auctionFinalPrice[_auctionId];
    }

    function revealAuction(uint256 _auctionId) public {
        // require(auctions[_auctionId].endTime < block.timestamp);

        uint256 auctionId=_auctionId;
        Bid[] memory totalBids = auctionBids[_auctionId];
        euint64 totalTokens = TFHE.asEuint64(auctions[_auctionId].tokenCount);
        TFHE.allowThis(totalTokens);
        euint64 tempTotalTokens = totalTokens;
        euint64 finalPrice = auctionFinalPrice[_auctionId];

        tempTotalTokens = totalTokens;
        TFHE.allowThis(tempTotalTokens);
        
        for (uint256 i = 0; i <totalBids.length; i++) {
            euint64 bidCount = totalBids[i].tokenAsked;
            TFHE.allowThis(bidCount);

            ebool isgreater = TFHE.gt(bidCount, tempTotalTokens);
            TFHE.allowThis(isgreater);
            bidCount = TFHE.select(isgreater, tempTotalTokens, bidCount);
            TFHE.allowThis(bidCount);

            ebool isTrue = TFHE.gt(tempTotalTokens, 0);
            TFHE.allowThis(isTrue);
            tempTotalTokens = TFHE.select(isTrue, TFHE.sub(tempTotalTokens, bidCount), tempTotalTokens);
            TFHE.allowThis(tempTotalTokens);
            TFHE.allowTransient(bidCount, auctions[auctionId].auctionTokenAddress);
            ConfidentialERC20(auctions[auctionId].auctionTokenAddress).transfer(totalBids[i].bidId, bidCount);

            euint64 x = TFHE.mul(totalBids[i].tokenAsked, totalBids[i].perTokenRate);
            TFHE.allowThis(x);
            euint64 y = TFHE.mul(bidCount, finalPrice);
            TFHE.allowThis(y);
            euint64 z = TFHE.sub(x, y);
            TFHE.allowThis(z);

            TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
            ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(totalBids[i].bidId, z);
        }
        TFHE.allowThis(totalTokens);
        TFHE.allowThis(tempTotalTokens);
        euint64 sellTokens = TFHE.sub(totalTokens, tempTotalTokens);
        TFHE.allowThis(sellTokens);
        TFHE.allowThis(finalPrice);
        euint64 toTransfer = TFHE.mul(sellTokens, finalPrice);
        // euint64 toTransfer = TFHE.asEuint64(1200);
        TFHE.allowThis(toTransfer);
        TFHE.allowTransient(toTransfer, auctions[auctionId].bidtokenAddress);
        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(
            auctions[auctionId].auctionOwner,
            toTransfer
        );

        
        TFHE.allowTransient(tempTotalTokens, auctions[auctionId].auctionTokenAddress);
        ConfidentialERC20(auctions[auctionId].auctionTokenAddress).transfer(
            auctions[auctionId].auctionOwner,
            tempTotalTokens
        );
        auctions[auctionId].isActive = false;
    }

}
