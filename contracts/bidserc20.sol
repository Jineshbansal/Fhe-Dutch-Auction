// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "./ERC20.sol";
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
    struct BidPlaintext {
        address bidId;
        uint256 auctionId;
        uint64 perTokenRate;
        uint64 tokenAsked;
    }

    struct BidQuantity {
        euint64 perTokenRate;
        euint64 tokenAsked;
    }
    struct BidPlaintextQuantity {
        uint64 perTokenRate;
        uint64 tokenAsked;
    }

    mapping(address => Auction[]) public MyAuctions; // drop after revealAuction for _auctionId           --
    mapping(uint256 => Auction) public auctions; // drop after revealAuction for _auctionId           --
    mapping(uint256 => Bid[]) private auctionBids; // drop after revealAuction for _auctionId           --
    mapping(uint256 => uint64) public auctionBidsEdgeWinner; // drop after revealAuction for _auctionId
    mapping(uint256 => uint64) public auctionAmountLeftForEdgeWinner; // drop after revealAuction for _auctionId
    mapping(uint256 => uint64) public auctionFinalPrice; // drop after revealAuction for _auctionId
    mapping(uint256 => BidPlaintext[]) public auctionPlaintextBids; // drop after revealAuction for _auctionId
    mapping(address => Bid[]) myBids; // drop in claimWonAuctionPrize and claimLostAuctionPrize --

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

        // Transfer the auction funds
        require(IERC20(_auctionTokenAddress).transferFrom(msg.sender, address(this), _tokenCount), "Transfer failed");
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

    function requestMixed(address bidId, uint256 auctionId, euint64 perTokenRate, euint64 tokenCount) internal {
        uint256[] memory cts = new uint256[](2);
        cts[0] = Gateway.toUint256(perTokenRate);
        cts[1] = Gateway.toUint256(tokenCount);
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.callbackMixed.selector,
            0,
            block.timestamp + 100,
            false
        );
        addParamsAddress(requestID, bidId);
        addParamsUint256(requestID, auctionId);
    }

    function callbackMixed(uint256 requestID, uint64 perTokenRate, uint64 tokenCount) public onlyGateway {
        uint256[] memory params = getParamsUint256(requestID);
        address[] memory paramsAddress = getParamsAddress(requestID);
        address bidId = paramsAddress[0];
        uint256 auctionId = params[0];
        auctionPlaintextBids[auctionId].push(BidPlaintext(bidId, auctionId, perTokenRate, tokenCount));
    }

    function decryptAllbids(uint256 _auctionId) public {
        require(msg.sender == auctions[_auctionId].auctionOwner);
        Bid[] memory totalBids = auctionBids[_auctionId];
        for (uint64 i = 0; i < totalBids.length; i++) {
            // decrypting the perTokenRate and tokenAsked in each bid
            requestMixed(
                totalBids[i].bidId,
                totalBids[i].auctionId,
                totalBids[i].perTokenRate,
                totalBids[i].tokenAsked
            );
        }
    }

    function getbidslength(uint256 _auctionId) public view returns (uint256) {
        return auctionPlaintextBids[_auctionId].length;
    }

    function getFinalPrice(uint256 _auctionId) public {
        uint256 auctionId = _auctionId;
        require(auctions[auctionId].isActive == true, "Auction is not active");
        
        require(
            auctionPlaintextBids[_auctionId].length == auctionBids[_auctionId].length,
            "All bids are not revealed yet"
        );
        BidPlaintext[] memory totalBids = auctionPlaintextBids[_auctionId];

        for (uint i = 0; i < totalBids.length; i++) {
            for (uint j = 0; j < totalBids.length - i - 1; j++) {
                if (totalBids[j].perTokenRate < totalBids[j + 1].perTokenRate) {
                    BidPlaintext memory temp = totalBids[j];
                    totalBids[j] = totalBids[j + 1];
                    totalBids[j + 1] = temp;
                }
            }
        }

        uint64 totalTokens = auctions[_auctionId].tokenCount;

        uint64 tempTotalTokens = totalTokens;

        uint64 finalPrice = 0;

        for (uint64 i = 0; i < totalBids.length; i++) {
            if (tempTotalTokens > 0) {
                if (totalBids[i].perTokenRate == 0) {
                    continue;
                }
                uint64 bidCount = totalBids[i].tokenAsked;
                if (bidCount > tempTotalTokens) {
                    bidCount = tempTotalTokens;
                }
                tempTotalTokens = tempTotalTokens - bidCount;
                finalPrice = totalBids[i].perTokenRate;
            } else {
                break;
            }
        }

        uint64 sellTokensWithProfit;

        for (uint64 i = 0; i < totalBids.length; i++) {
            if (totalBids[i].perTokenRate > finalPrice) {
                sellTokensWithProfit += totalBids[i].tokenAsked;
            }
            if (finalPrice == totalBids[i].perTokenRate) {
                auctionBidsEdgeWinner[_auctionId] += totalBids[i].tokenAsked;
            }
        }
        if (tempTotalTokens > 0) {
            auctionAmountLeftForEdgeWinner[_auctionId] = (totalTokens - tempTotalTokens) - sellTokensWithProfit;
        } else {
            auctionAmountLeftForEdgeWinner[_auctionId] = totalTokens - sellTokensWithProfit;
        }
        auctions[_auctionId].isActive = false;
        auctionFinalPrice[_auctionId] = finalPrice;
        uint64 sellTokens = totalTokens - tempTotalTokens;
        euint64 toTransfer = TFHE.asEuint64(sellTokens * finalPrice);
        TFHE.allowTransient(toTransfer, auctions[_auctionId].bidtokenAddress);
        ConfidentialERC20(auctions[_auctionId].bidtokenAddress).transfer(auctions[_auctionId].auctionOwner, toTransfer);

        IERC20(auctions[_auctionId].auctionTokenAddress).transfer(auctions[_auctionId].auctionOwner, tempTotalTokens);
    }

    function reclaimTokens(uint256 _auctionId) public {
        require(auctions[_auctionId].isActive == false, "Auction is still active");
        uint256 auctionId = _auctionId;
        uint64 finalPrice = auctionFinalPrice[_auctionId];
        BidPlaintext[] memory totalBids = auctionPlaintextBids[_auctionId];
        for (uint i = 0; i < totalBids.length; i++) {
            if (totalBids[i].bidId == msg.sender) {
                if (totalBids[i].perTokenRate > finalPrice) {
                    uint64 x = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    uint64 y = totalBids[i].tokenAsked * finalPrice;
                    euint64 z = TFHE.asEuint64(x - y);
                    TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
                    ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(totalBids[i].bidId, z);
                    IERC20(auctions[auctionId].auctionTokenAddress).transfer(
                        totalBids[i].bidId,
                        totalBids[i].tokenAsked
                    );
                } else if (totalBids[i].perTokenRate == finalPrice) {
                    uint64 tokenGet = (totalBids[i].tokenAsked * auctionAmountLeftForEdgeWinner[_auctionId]) /
                        auctionBidsEdgeWinner[_auctionId];
                    uint64 x = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    uint64 y = tokenGet * finalPrice;
                    euint64 z = TFHE.asEuint64(x - y);
                    TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
                    ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(totalBids[i].bidId, z);
                    IERC20(auctions[auctionId].auctionTokenAddress).transfer(totalBids[i].bidId, tokenGet);
                } else {
                    uint64 x = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
                    euint64 z = TFHE.asEuint64(x);
                    TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
                    ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(totalBids[i].bidId, z);
                }
            }
        }
    }

    function revealAuction(uint256 _auctionId) public {
        // // require(auctions[_auctionId].endTime < block.timestamp);
        // BidPlaintext[] memory totalBids = auctionPlaintextBids[_auctionId];
        // uint256 auctionId = _auctionId;
        // uint256 auctionAddress = auctionId;
        // uint64 finalPrice=getFinalPrice(_auctionId);
        // uint64 totalTokens = auctions[_auctionId].tokenCount;
        // uint64 count=0;
        // uint64 tempTotalTokens = totalTokens;
        // for (uint64 i = 0; i < totalBids.length; i++) {
        //     uint64 bidCount = totalBids[i].tokenAsked;
        //     if (bidCount > tempTotalTokens) {
        //         bidCount = tempTotalTokens;
        //     }
        //     if (tempTotalTokens > 0 && totalBids[i].perTokenRate >= finalPrice) {
        //         tempTotalTokens = tempTotalTokens - bidCount;
        //         IERC20(auctions[auctionAddress].auctionTokenAddress).transfer(totalBids[i].bidId, bidCount);
        //         uint64 x = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
        //         uint64 y = bidCount * finalPrice;
        //         euint64 z = TFHE.asEuint64(x - y);
        //         require((x-y)==0,"Z is not equal to 0");
        //         TFHE.allowTransient(z, auctions[auctionAddress].bidtokenAddress);
        //         ConfidentialERC20(auctions[auctionAddress].bidtokenAddress).transfer(totalBids[i].bidId, z);
        //     }else{
        //         count++;
        //         uint64 x = totalBids[i].tokenAsked * totalBids[i].perTokenRate;
        //         euint64 z = TFHE.asEuint64(x);
        //         TFHE.allowTransient(z, auctions[auctionAddress].bidtokenAddress);
        //         ConfidentialERC20(auctions[auctionAddress].bidtokenAddress).transfer(totalBids[i].bidId, z);
        //     }
        // }
        // // require(count==16,"Count is not equal to 16");
        // uint64 sellTokens = totalTokens - tempTotalTokens;
        // require(sellTokens == totalTokens, "Sell tokens is not equal to total tokens");
        // euint64 toTransfer = TFHE.asEuint64(sellTokens * finalPrice);
        // TFHE.allowTransient(toTransfer, auctions[auctionAddress].bidtokenAddress);
        // ConfidentialERC20(auctions[auctionAddress].bidtokenAddress).transfer(
        //     auctions[auctionAddress].auctionOwner,
        //     toTransfer
        // );
        // IERC20(auctions[auctionAddress].auctionTokenAddress).transfer(
        //     auctions[auctionAddress].auctionOwner,
        //     tempTotalTokens
        // );
        // auctions[auctionAddress].isActive = false;
    }

    function updateBidInc(
        uint256 _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        uint256 auctionId = _auctionId;
        euint64 updateTokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 updateTokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);
        address bidderId = msg.sender;

        TFHE.allowThis(updateTokenRate);
        TFHE.allowThis(updateTokenAsked);
        for (uint i = 0; i < myBids[bidderId].length; i++) {
            if (myBids[bidderId][i].auctionId == auctionId) {
                euint64 x = TFHE.mul(myBids[bidderId][i].perTokenRate, auctionBids[auctionId][i].tokenAsked);
                TFHE.allowThis(x);
                euint64 y = TFHE.mul(updateTokenRate, updateTokenAsked);
                TFHE.allowThis(y);
                auctionBids[auctionId][i].perTokenRate = updateTokenRate;
                auctionBids[auctionId][i].tokenAsked = updateTokenAsked;
                TFHE.allowThis(auctionBids[auctionId][i].perTokenRate);
                TFHE.allowThis(auctionBids[auctionId][i].tokenAsked);
                euint64 z = TFHE.sub(y, x);
                TFHE.allowThis(z);

                TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
                ConfidentialERC20(auctions[auctionId].bidtokenAddress).transferFrom(msg.sender, address(this), z);

                myBids[bidderId][i].perTokenRate = updateTokenRate;
                myBids[bidderId][i].tokenAsked = updateTokenAsked;
                TFHE.allowThis(myBids[bidderId][i].perTokenRate);
                TFHE.allowThis(myBids[bidderId][i].tokenAsked);
            }
        }
    }

    function updateBidDec(
        uint256 _auctionId,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        uint256 auctionId = _auctionId;
        euint64 updateTokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 updateTokenAsked = TFHE.asEuint64(_tokenCount, _tokenCountproof);
        address bidderId = msg.sender;

        TFHE.allowThis(updateTokenRate);
        TFHE.allowThis(updateTokenAsked);
        for (uint i = 0; i < myBids[bidderId].length; i++) {
            if (myBids[bidderId][i].auctionId == auctionId) {
                euint64 x = TFHE.mul(myBids[bidderId][i].perTokenRate, auctionBids[auctionId][i].tokenAsked);
                TFHE.allowThis(x);
                euint64 y = TFHE.mul(updateTokenRate, updateTokenAsked);
                TFHE.allowThis(y);
                auctionBids[auctionId][i].perTokenRate = updateTokenRate;
                auctionBids[auctionId][i].tokenAsked = updateTokenAsked;
                TFHE.allowThis(auctionBids[auctionId][i].perTokenRate);
                TFHE.allowThis(auctionBids[auctionId][i].tokenAsked);
                euint64 z = TFHE.sub(x, y);
                TFHE.allowThis(z);
                TFHE.allowTransient(z, auctions[auctionId].bidtokenAddress);
                ConfidentialERC20(auctions[auctionId].bidtokenAddress).transfer(msg.sender, z);
                myBids[bidderId][i].perTokenRate = updateTokenRate;
                myBids[bidderId][i].tokenAsked = updateTokenAsked;
                TFHE.allowThis(myBids[bidderId][i].perTokenRate);
                TFHE.allowThis(myBids[bidderId][i].tokenAsked);
            }
        }
    }

    // --------------UTILS----------------
    // function getAuction(address _creator) public view returns (Auction memory) {
    //     return auctions[_creator];
    // }

    // function getAuctions() public view returns (Auction[] memory) {
    //     return allAuctions;
    // }

    // function hasAuction() public view returns (bool) {
    //     return auctions[msg.sender].auctionId == msg.sender;
    // }

    // function getMyBids() public view returns (Bid[] memory) {
    //     return myBids[msg.sender];
    // }

    // function getBidsForAuction(address _auctionId) public view returns (Bid[] memory) {
    //     return auctionBids[_auctionId];
    // }

    // --------------MAJORS------------------

    // One person can create only one auction
}
