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

    constructor() {
        owner = msg.sender;
    }

    struct Auction {
        address auctionTokenAddress;
        address bidtokenAddress;
        string auctionTitle;
        address auctionId;
        address auctionOwner;
        string tokenName;
        uint64 tokenCount;
        uint64 minCount;
        uint256 startingBidTime;
        uint256 endTime;
    }

    struct Bid {
        address bidId;
        address auctionId;
        euint64 perTokenRate;
        euint64 tokenAsked;
    }

    struct BidQuantity {
        euint64 perTokenRate;
        euint64 tokenAsked;
    }

    mapping(address => mapping(address => Bid)) public bids; // drop after revealAuction for _auctionId           --
    mapping(address => Auction) public auctions; // drop after revealAuction for _auctionId           --
    mapping(address => Bid[]) public auctionBids; // drop after revealAuction for _auctionId           --
    Auction[] public allAuctions; // drop after claimLeftAuctionStake for _auctionId   --
    Bid[] public allBids; // for testing purposes                              --
    mapping(address => Bid[]) winningBids; // drop in claimLeftAuctionStake by bidId            --
    mapping(address => uint64) leftAuctionStake; // drop one by one in claimLeftAuctionStake          --
    mapping(address => mapping(address => uint64)) wonAuctionPrize; // drop in claimWonAuctionPrize --
    mapping(address => mapping(address => uint64)) lostAuctionStake; // drop in claimLostAuctionStake --
    mapping(address => Bid[]) myBids; // drop in claimWonAuctionPrize and claimLostAuctionPrize --

    function createAuction(
        address _auctionTokenAddress,
        address _bidTokenAddress,
        string calldata _auctionTitle,
        uint64 _tokenCount,
        uint256 _startingBid, // may be same as start time
        uint256 _endTime
    ) public {
        require(auctions[msg.sender].auctionId != msg.sender, "Auction already exists");

        Auction memory newAuction = Auction({
            auctionTokenAddress: _auctionTokenAddress,
            bidtokenAddress: _bidTokenAddress,
            auctionTitle: _auctionTitle,
            auctionId: msg.sender,
            tokenName: "auctionToken",
            tokenCount: _tokenCount,
            startingBidTime: block.timestamp + _startingBid,
            minCount: (_tokenCount * 1) / 100,
            endTime: block.timestamp + _endTime
        });

        auctions[msg.sender] = newAuction;
        allAuctions.push(newAuction);

        // Transfer the auction funds
        euint64 encryptedAmount = TFHE.asEuint64(_tokenCount);
        TFHE.allowThis(encryptedAmount);
        TFHE.allowTransient(encryptedAmount, _auctionTokenAddress);
        require(ConfidentialERC20(_auctionTokenAddress).transferFrom(msg.sender,address(this), encryptedAmount));
    }

    function initiateBid(
        address _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        address auctionId=_auctionId;
        euint64 tokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 tokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);
        address bidderId = msg.sender;

        TFHE.allowThis(tokenRate);
        TFHE.allowThis(tokenAsked);
        Bid memory newBid = Bid({
            auctionId:auctionId ,
            bidId:bidderId,
            perTokenRate: tokenRate,
            tokenAsked: tokenAsked
        });

        TFHE.allowThis(newBid.perTokenRate);
        TFHE.allowThis(newBid.tokenAsked);

        myBids[bidderId].push(newBid);

        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].perTokenRate);
        TFHE.allowThis(myBids[bidderId][myBids[bidderId].length - 1].tokenAsked);

        auctionBids[auctionId].push(newBid);
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].perTokenRate);
        TFHE.allowThis(auctionBids[auctionId][auctionBids[auctionId].length - 1].tokenAsked);

        euint64 tokenSubmit = TFHE.mul(tokenAsked, tokenRate);
        TFHE.allowThis(tokenSubmit);
        TFHE.allowTransient(tokenSubmit, auctions[auctionId].bidtokenAddress);
        ConfidentialERC20(auctions[auctionId].bidtokenAddress).transferFrom(msg.sender,address(this),tokenSubmit);

    }

    function revealAuction(address _auctionId) public returns (Bid[] memory) {

        // require(auctions[_auctionId].endTime < block.timestamp);
        address auctionId=_auctionId;
        Bid[] memory totalBids = auctionBids[_auctionId];
        BidQuantity[] memory totalBidsQuantity = new BidQuantity[](totalBids.length); 
        for(uint64 i=0;i<totalBids.length;i++){
            TFHE.allowThis(totalBids[i].perTokenRate);
            TFHE.allowThis(totalBids[i].tokenAsked);
            totalBidsQuantity[i].perTokenRate=totalBids[i].perTokenRate;
            totalBidsQuantity[i].tokenAsked=totalBids[i].tokenAsked;
            TFHE.allowThis(totalBidsQuantity[i].perTokenRate);
            TFHE.allowThis(totalBidsQuantity[i].tokenAsked);
        }

        for (uint i = 0; i < totalBids.length; i++) {
            for (uint j = 0; j < totalBids.length - i - 1; j++) {
                ebool isTrue=TFHE.gt(totalBidsQuantity[j].perTokenRate, totalBidsQuantity[j + 1].perTokenRate);
                TFHE.allowThis(isTrue);
                BidQuantity memory temp=totalBidsQuantity[j];
                TFHE.allowThis(temp.perTokenRate);
                TFHE.allowThis(temp.tokenAsked);

                
                totalBidsQuantity[j].perTokenRate = TFHE.select(isTrue, totalBidsQuantity[j + 1].perTokenRate, totalBidsQuantity[j].perTokenRate);
                totalBidsQuantity[j].tokenAsked = TFHE.select(isTrue, totalBidsQuantity[j + 1].tokenAsked, totalBidsQuantity[j].tokenAsked);
                TFHE.allowThis(totalBidsQuantity[j].perTokenRate);
                TFHE.allowThis(totalBidsQuantity[j].tokenAsked);

            }
        }


        euint64 totalTokens = TFHE.asEuint64(auctions[_auctionId].tokenCount);
        TFHE.allowThis(totalTokens);

        euint64 tempTotalTokens = totalTokens;
        TFHE.allowThis(tempTotalTokens);

        euint64 finalPrice=TFHE.asEuint64(0);
        TFHE.allowThis(finalPrice);
        for (uint64 i = 0; i < totalBids.length; i++) {

            ebool isTrue=TFHE.gt(tempTotalTokens,0);
            TFHE.allowThis(isTrue);
            euint64 bidCount = TFHE.select(isTrue,totalBidsQuantity[i].tokenAsked,TFHE.asEuint64(0));
            TFHE.allowThis(bidCount);
            
            bidCount=TFHE.select(isTrue,TFHE.select(TFHE.gt(bidCount,tempTotalTokens), tempTotalTokens, bidCount),bidCount);
            TFHE.allowThis(bidCount);
            tempTotalTokens=TFHE.select(isTrue,TFHE.sub(tempTotalTokens,bidCount),tempTotalTokens);
            TFHE.allowThis(tempTotalTokens);
            finalPrice = TFHE.select(isTrue,totalBidsQuantity[i].perTokenRate,finalPrice);
            TFHE.allowThis(finalPrice);
           
        }
        address auctionAddress=auctionId;
        tempTotalTokens = totalTokens;
        for (uint64 i = 0; i < totalBids.length; i++) {
            euint64 bidCount = totalBids[i].tokenAsked;
            TFHE.allowThis(bidCount);
            // if (bidCount > tempTotalTokens) {
            //     bidCount = tempTotalTokens;
            // }
            ebool isgreater=TFHE.gt(bidCount,tempTotalTokens);
            TFHE.allowThis(isgreater);
            bidCount=TFHE.select(isgreater, tempTotalTokens, bidCount);
            TFHE.allowThis(bidCount);

            euint64 subtemp=TFHE.sub(tempTotalTokens,bidCount);
            TFHE.allowThis(subtemp);
            ebool isTrue=TFHE.gt(tempTotalTokens,0);
            TFHE.allowThis(isTrue);
            tempTotalTokens=TFHE.select(isTrue,subtemp,tempTotalTokens);
            TFHE.allowThis(tempTotalTokens);
            TFHE.allowTransient(bidCount, auctions[auctionId].auctionTokenAddress);
            ConfidentialERC20(auctions[auctionId].auctionTokenAddress).transfer(totalBids[i].bidId, bidCount);

            euint64 x=TFHE.mul(totalBids[i].tokenAsked, totalBids[i].perTokenRate);
            TFHE.allowThis(x);
            euint64 y=TFHE.mul(bidCount, finalPrice);
            TFHE.allowThis(y);
            euint64 z=TFHE.sub(x,y);
            TFHE.allowThis(z);

            
            TFHE.allowTransient(z, auctions[auctionAddress].bidtokenAddress);
            ConfidentialERC20(auctions[auctionAddress].bidtokenAddress).transfer(totalBids[i].bidId, z);
        }
        euint64 sellTokens=TFHE.sub(totalTokens,tempTotalTokens);
        TFHE.allowThis(sellTokens);

        euint64 toTransfer=TFHE.mul(sellTokens,finalPrice);
        TFHE.allowThis(toTransfer);
        TFHE.allowTransient(toTransfer, auctions[auctionAddress].bidtokenAddress);
        ConfidentialERC20(auctions[auctionAddress].bidtokenAddress).transfer(_auctionId, toTransfer);
        TFHE.allowTransient(tempTotalTokens, auctions[auctionAddress].auctionTokenAddress);
        ConfidentialERC20(auctions[auctionAddress].auctionTokenAddress).transfer(_auctionId, tempTotalTokens);
    }



    // --------------UTILS----------------
    function getAuction(address _creator) public view returns (Auction memory) {
        return auctions[_creator];
    }

    function getAuctions() public view returns (Auction[] memory) {
        return allAuctions;
    }

    function hasAuction() public view returns (bool) {
        return auctions[msg.sender].auctionId == msg.sender;
    }

    function getMyBids() public view returns (Bid[] memory) {
        return myBids[msg.sender];
    }

    function getBidsForAuction(address _auctionId) public view returns (Bid[] memory) {
        return auctionBids[_auctionId];
    }

    // --------------MAJORS------------------

    // One person can create only one auction

}
