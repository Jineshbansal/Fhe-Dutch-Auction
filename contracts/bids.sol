// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";

contract BlindAuction is SepoliaZamaFHEVMConfig {
    address public owner;

    // TESTING
    /// @dev Encrypted state variables
    euint256 counter;

    constructor() {
        owner = msg.sender;
        counter = TFHE.asEuint256(0);
        TFHE.allowThis(counter);
    }

    // struct Auction {
    //     address auctionId;
    //     string tokenName;
    //     uint256 tokenCount;
    //     uint256 minCount;
    //     uint256 startingBidTime;
    //     uint256 endTime;
    // }

    // struct Bid {
    //     address auctionId;
    //     address bidId;
    //     uint256 perTokenRate;
    //     uint256 tokenCount;
    // }

    // mapping(address => mapping(address => Bid)) public bids;
    // mapping(address => Auction) public auctions;
    // mapping(address => address[]) public auctionBidders;
    // Auction[] public allAuctions;
    // Bid[] public allBids;

    // // -------------TESTING---------------
    // function increment() public {
    //     counter = TFHE.add(counter, TFHE.asEuint256(1));
    //     TFHE.allowThis(counter);
    // }

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

    // function sortBids(
    //     Bid[] memory relBids
    // ) internal pure returns (Bid[] memory) {
    //     uint256 n = relBids.length;

    //     for (uint256 i = 0; i < n - 1; i++) {
    //         for (uint256 j = 0; j < n - i - 1; j++) {
    //             if (relBids[j].perTokenRate < relBids[j + 1].perTokenRate) {
    //                 // Swap relBids[j] and relBids[j + 1]
    //                 Bid memory temp = relBids[j];
    //                 relBids[j] = relBids[j + 1];
    //                 relBids[j + 1] = temp;
    //             }
    //         }
    //     }
    //     return relBids;
    // }

    // function getBidsForAuction(
    //     address _auctionId
    // ) public view returns (Bid[] memory) {
    //     address[] memory bidders = auctionBidders[_auctionId];
    //     Bid[] memory auctionBids = new Bid[](bidders.length);

    //     for (uint256 i = 0; i < bidders.length; i++) {
    //         auctionBids[i] = bids[_auctionId][bidders[i]];
    //     }

    //     return sortBids(auctionBids);
    // }

    // // --------------MAJORS------------------

    // // One person can create only one auction
    // function createAuction(
    //     string calldata _tokenName,
    //     uint256 _tokenCount,
    //     uint256 _startingBid, // may be same as start time
    //     uint256 _endTime
    // ) public returns (bool) {
    //     if (auctions[msg.sender].auctionId == msg.sender) {
    //         return false;
    //     }

    //     Auction memory newAuction = Auction({
    //         auctionId: msg.sender,
    //         tokenName: _tokenName,
    //         tokenCount: _tokenCount,
    //         startingBidTime: block.timestamp + _startingBid,
    //         minCount: (_tokenCount * 1) / 100,
    //         endTime: block.timestamp + _endTime
    //     });

    //     auctions[msg.sender] = newAuction;
    //     allAuctions.push(newAuction);
    //     return true;
    // }

    // function initiateBid(
    //     address _auctionId,
    //     uint256 _tokenRate,
    //     uint256 _tokenCount
    // ) public returns (bool) {
    //     require(!(bids[_auctionId][msg.sender].bidId == msg.sender));
    //     Auction memory auction = auctions[_auctionId];

    //     if (
    //         (_tokenCount < auction.minCount) ||
    //         (auction.startingBidTime > block.timestamp)
    //     ) {
    //         return false;
    //     }

    //     Bid memory newBid = Bid({
    //         auctionId: _auctionId,
    //         bidId: msg.sender,
    //         perTokenRate: _tokenRate,
    //         tokenCount: _tokenCount
    //     });

    //     bids[_auctionId][msg.sender] = newBid;
    //     auctionBidders[_auctionId].push(msg.sender);
    //     allBids.push(newBid);
    //     return true;
    // }

    // function revealAuction() public view returns (Bid[] memory) {
    //     require(
    //         (auctions[msg.sender].auctionId == msg.sender) &&
    //             (auctions[msg.sender].endTime < block.timestamp)
    //     );

    //     Bid[] memory relBids = getBidsForAuction((msg.sender));
    //     uint256 tokenCount = auctions[msg.sender].tokenCount;
    //     Bid[] memory winningBids = new Bid[](relBids.length);

    //     for (uint256 i = 0; i < relBids.length; i++) {
    //         if (tokenCount < relBids[i].tokenCount) {
    //             winningBids[i] = relBids[i];
    //             break;
    //         }

    //         winningBids[i] = relBids[i];
    //         tokenCount -= relBids[i].tokenCount;
    //     }

    //     return winningBids;
    // }
}
