// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract BlindAuction is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    address public owner;
    ERC20 private auctionToken;
    ERC20 private token2;
    // ERC20 private token2;

    constructor(address auctionTokenAddress , address token2Address) {
        // Gateway.setGateway(Gateway.gatewayContractAddress());
        auctionToken = ERC20(auctionTokenAddress);
        token2 = ERC20(token2Address);
        owner = msg.sender;

    }

    struct Auction {
        string auctionTitle;
        address auctionId;
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
    function createAuction(
        string calldata _auctionTitle,
        uint64 _tokenCount,
        uint256 _startingBid, // may be same as start time
        uint256 _endTime
    ) public {
        require(auctions[msg.sender].auctionId != msg.sender, "Auction already exists");

        Auction memory newAuction = Auction({
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
        TFHE.allowTransient(encryptedAmount, address(auctionToken));
        require(auctionToken.transferFrom(msg.sender,address(this), encryptedAmount));
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
        TFHE.allowTransient(tokenSubmit, address(token2));
        token2.transferFrom(msg.sender,address(this),tokenSubmit);
        // Gateway.requestDecryption(cts, this.callbackInitiateBid.selector, 0, block.timestamp + 100, false);
    }

    function revealAuction(address _auctionId) public returns (Bid[] memory) {

        // require(auctions[_auctionId].endTime < block.timestamp);

        Bid[] memory totalBids = auctionBids[_auctionId];
        for(uint64 i=0;i<totalBids.length;i++){
            TFHE.allowThis(totalBids[i].perTokenRate);
            TFHE.allowThis(totalBids[i].tokenAsked);
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
            euint64 bidCount = TFHE.select(isTrue,totalBids[i].tokenAsked,TFHE.asEuint64(0));
            TFHE.allowThis(bidCount);
            
            bidCount=TFHE.select(isTrue,TFHE.select(TFHE.gt(bidCount,tempTotalTokens), tempTotalTokens, bidCount),bidCount);
            TFHE.allowThis(bidCount);
            tempTotalTokens=TFHE.select(isTrue,TFHE.sub(tempTotalTokens,bidCount),tempTotalTokens);
            TFHE.allowThis(tempTotalTokens);
            finalPrice = TFHE.select(isTrue,totalBids[i].perTokenRate,finalPrice);
            TFHE.allowThis(finalPrice);
           
        }
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
            TFHE.allowTransient(bidCount, address(auctionToken));
            auctionToken.transfer(totalBids[i].bidId, bidCount);

            euint64 x=TFHE.mul(totalBids[i].tokenAsked, totalBids[i].perTokenRate);
            TFHE.allowThis(x);
            euint64 y=TFHE.mul(bidCount, finalPrice);
            TFHE.allowThis(y);
            euint64 z=TFHE.sub(x,y);
            TFHE.allowThis(z);

            TFHE.allowTransient(z, address(token2));
            token2.transfer(totalBids[i].bidId, z);
        }
        euint64 sellTokens=TFHE.sub(totalTokens,tempTotalTokens);
        TFHE.allowThis(sellTokens);

        euint64 toTransfer=TFHE.mul(sellTokens,finalPrice);
        TFHE.allowThis(toTransfer);
        TFHE.allowTransient(toTransfer, address(token2));
        token2.transfer(_auctionId, toTransfer);
        TFHE.allowTransient(tempTotalTokens, address(auctionToken));
        auctionToken.transfer(_auctionId, tempTotalTokens);
    }

}
