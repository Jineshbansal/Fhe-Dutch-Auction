// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "./ERC20.sol";
import "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { SepoliaZamaGatewayConfig } from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract BlindAuction is SepoliaZamaFHEVMConfig, SepoliaZamaGatewayConfig, GatewayCaller {
    address public owner;

    ERC20 private token1;
    // ERC20 private token2;

    constructor(address token1Address) {
        Gateway.setGateway(Gateway.gatewayContractAddress());
        token1 = ERC20(token1Address);
        owner = msg.sender;
    }

    struct Auction {
        address auctionId;
        string tokenName;
        uint256 tokenCount;
        uint256 minCount;
        uint256 startingBidTime;
        uint256 endTime;
    }

    struct Bid {
        eaddress auctionId;
        eaddress bidId;
        euint64 perTokenRate;
        euint64 tokenCount;
    }

    mapping(address => mapping(address => Bid)) public bids;
    mapping(address => Auction) public auctions;
    mapping(address => address[]) public auctionBidders;
    Auction[] public allAuctions;
    Bid[] public allBids;

    // -------------TESTING---------------

    euint256 public counter;
    uint256 public counter_anon = 10;

    function increment() public {
        counter = TFHE.add(counter, TFHE.asEuint256(1));
        TFHE.allowThis(counter);
    }

    function getCounter() public {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(counter);
        Gateway.requestDecryption(cts, this.callbackCounter.selector, 0, block.timestamp + 2, false);
    }

    /// @notice Callback function for counter decryption
    /// @param decryptedInput The decrypted counter value
    /// @return The decrypted value
    function callbackCounter(uint256, uint256 decryptedInput) public onlyGateway returns (uint256) {
        counter_anon = decryptedInput;
        return decryptedInput;
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

    // function sortBids(Bid[] memory relBids) internal pure returns (Bid[] memory) {
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

    // function getBidsForAuction(address _auctionId) public view returns (Bid[] memory) {
    //     address[] memory bidders = auctionBidders[_auctionId];
    //     Bid[] memory auctionBids = new Bid[](bidders.length);

    //     for (uint256 i = 0; i < bidders.length; i++) {
    //         auctionBids[i] = bids[_auctionId][bidders[i]];
    //     }

    //     return sortBids(auctionBids);
    // }

    // --------------MAJORS------------------

    // One person can create only one auction
    function createAuction(
        string calldata _tokenName,
        uint64 _tokenCount,
        uint256 _startingBid, // may be same as start time
        uint256 _endTime,
        einput _encryptedAmount,
        bytes calldata inputProof
    ) public {
        require(auctions[msg.sender].auctionId != msg.sender, "Auction already exists");

        Auction memory newAuction = Auction({
            auctionId: msg.sender,
            tokenName: _tokenName,
            tokenCount: _tokenCount,
            startingBidTime: block.timestamp + _startingBid,
            minCount: (_tokenCount * 1) / 100,
            endTime: block.timestamp + _endTime
        });

        auctions[msg.sender] = newAuction;
        allAuctions.push(newAuction);

        // Transfer the auction funds
        euint64 encryptedAmount = TFHE.asEuint64(_encryptedAmount, inputProof);
        TFHE.allowTransient(encryptedAmount, address(token1));
        require(token1.transfer(address(this), encryptedAmount));
    }

    // function initiateBid(eaddress _auctionId, euint64 _tokenRate, euint64 _tokenCount) public {
    //     // require(
    //     //     bids[_auctionId][TFHE.asEaddress(msg.sender)].bidId != TFHE.asEaddress(msg.sender),
    //     //     "Bid already exists"
    //     // );

    //     // require(TFHE.ne(bids[TFHE.toUin][TFHE.asEaddress(msg.sender)].bidId, TFHE.asEaddress(msg.sender)));

    //     Auction memory auction = auctions[_auctionId];

    //     if ((_tokenCount < auction.minCount) || (auction.startingBidTime > block.timestamp)) {
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
    //     require((auctions[msg.sender].auctionId == msg.sender) && (auctions[msg.sender].endTime < block.timestamp));

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
