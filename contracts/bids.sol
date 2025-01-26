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
        // Gateway.setGateway(Gateway.gatewayContractAddress());
        token1 = ERC20(token1Address);
        owner = msg.sender;

        counter = TFHE.asEuint256(15);
        TFHE.allowThis(counter);
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
        address auctionId;
        address bidId;
        uint64 perTokenRate;
        uint64 tokenCount;
    }

    mapping(address => mapping(address => Bid)) public bids; //             drop after revealAuction for _auctionId           --
    mapping(address => Auction) public auctions; //                         drop after revealAuction for _auctionId           --
    mapping(address => address[]) public auctionBidders; //                 drop after revealAuction for _auctionId           --
    Auction[] public allAuctions; //                                        drop after claimLeftAuctionStake for _auctionId   --
    Bid[] public allBids; //                                                for testing purposes                              --
    mapping(address => Bid[]) winningBids; //                               drop in claimLeftAuctionStake by bidId            --
    mapping(address => uint256) leftAuctionStake; //                        drop one by one in claimLeftAuctionStake          --
    mapping(address => mapping(address => uint256)) wonAuctionPrize; //     drop one by one in claimWonAuctionPrize           --
    mapping(address => mapping(address => uint256)) lostAuctionStake; //    drop one by one in claimLostAuctionStake          --
    mapping(address => Bid[]) myBids;

    // -------------TESTING---------------

    euint256 public counter;
    uint256 public counter_anon;

    function increment() public {
        counter = TFHE.add(counter, TFHE.asEuint256(1));
        TFHE.allowThis(counter);
    }

    function getCounter() public {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(counter);
        Gateway.requestDecryption(cts, this.callbackCounter.selector, 0, block.timestamp + 1, true);
    }

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

    function getMyBids() public view returns (Bid[] memory) {
        return myBids[msg.sender];
    }

    function sortBids(Bid[] memory relBids) internal pure returns (Bid[] memory) {
        uint256 n = relBids.length;

        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (relBids[j].perTokenRate < relBids[j + 1].perTokenRate) {
                    // Swap relBids[j] and relBids[j + 1]
                    Bid memory temp = relBids[j];
                    relBids[j] = relBids[j + 1];
                    relBids[j + 1] = temp;
                }
            }
        }
        return relBids;
    }

    function getBidsForAuction(address _auctionId) public view returns (Bid[] memory) {
        address[] memory bidders = auctionBidders[_auctionId];
        Bid[] memory auctionBids = new Bid[](bidders.length);

        for (uint256 i = 0; i < bidders.length; i++) {
            auctionBids[i] = bids[_auctionId][bidders[i]];
        }

        return sortBids(auctionBids);
    }

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

    function initiateBid(eaddress _auctionId, euint64 _tokenRate, euint64 _tokenCount) public {
        eaddress _bidderId = TFHE.asEaddress(msg.sender);
        TFHE.allowThis(_bidderId);

        // Decrypt all the params
        uint256[] memory cts = new uint256[](4);
        cts[0] = Gateway.toUint256(_auctionId);
        cts[1] = Gateway.toUint256(_tokenRate);
        cts[2] = Gateway.toUint256(_tokenCount);
        cts[3] = Gateway.toUint256(_bidderId);
        Gateway.requestDecryption(cts, this.callbackInitiateBid.selector, 0, block.timestamp + 100, false);
    }

    function callbackInitiateBid(
        uint256,
        address _auctionId,
        uint64 _tokenRate,
        uint64 _tokenCount,
        address _bidderId
    ) public onlyGateway returns (bool) {
        // Now carry out the whole process
        require(bids[_auctionId][_bidderId].bidId != _bidderId);
        Auction memory auction = auctions[_auctionId];
        require(_tokenCount > auction.minCount);
        require(auction.startingBidTime < block.timestamp);

        Bid memory newBid = Bid({
            auctionId: _auctionId,
            bidId: msg.sender,
            perTokenRate: _tokenRate,
            tokenCount: _tokenCount
        });

        bids[_auctionId][msg.sender] = newBid;
        auctionBidders[_auctionId].push(msg.sender);
        allBids.push(newBid);

        // TODO! Transfer funds of the bid, new ERC20 Token2

        return true;
    }

    function revealAuction(address _auctionId) public returns (Bid[] memory) {
        require((auctions[msg.sender].auctionId == msg.sender) && (auctions[msg.sender].endTime < block.timestamp));

        require(auctions[_auctionId].auctionId == msg.sender);
        require(auctions[_auctionId].endTime < block.timestamp);

        Bid[] memory relBids = getBidsForAuction(msg.sender);
        uint256 tokenCount = auctions[msg.sender].tokenCount;
        Bid[] memory _winningBids = new Bid[](relBids.length);

        for (uint256 i = 0; i < relBids.length; i++) {
            if (0 < tokenCount) {
                // Winning Bids
                if (tokenCount > relBids[i].tokenCount) {
                    _winningBids[i] = relBids[i];
                    wonAuctionPrize[_auctionId][relBids[i].bidId] = relBids[i].tokenCount;
                    tokenCount -= relBids[i].tokenCount;
                } else {
                    // Partial Win
                    _winningBids[i] = relBids[i];
                    wonAuctionPrize[_auctionId][relBids[i].bidId] = tokenCount;
                    tokenCount = 0;
                }
            } else {
                // Losing Bids
                lostAuctionStake[_auctionId][relBids[i].bidId] = relBids[i].tokenCount;
            }
        }

        if (tokenCount > 0) {
            leftAuctionStake[_auctionId] = tokenCount;
        }

        winningBids[_auctionId] = _winningBids;
        return _winningBids;
    }

    function claimWonAuctionPrize(address _auctionId) public {
        require(wonAuctionPrize[_auctionId][msg.sender] > 0, "Sender is a fraud");

        uint256 _prizeAmount = wonAuctionPrize[_auctionId][msg.sender];
        delete (wonAuctionPrize[_auctionId][msg.sender]);

        // TODO! Transfer this amount to the auction Winner
    }

    function claimLeftAuctionStake() public {
        require(leftAuctionStake[msg.sender] > 0, "You don't own any auction");

        uint256 _redeemAmount = leftAuctionStake[msg.sender];

        // Delete all the data about this auction
        delete (leftAuctionStake[msg.sender]);
        delete (winningBids[msg.sender]);
        delete (auctions[msg.sender]);
        address[] memory bidders = auctionBidders[msg.sender];
        for (uint256 i = 0; i < bidders.length; i++) {
            delete bids[msg.sender][bidders[i]];
        }
        delete auctionBidders[msg.sender];

        for (uint256 i = 0; i < allAuctions.length; i++) {
            if (allAuctions[i].auctionId == msg.sender) {
                allAuctions[i] = allAuctions[allAuctions.length - 1];
                allAuctions.pop();
            }
        }

        // TODO! Transfer this amount to the auction Owner
    }

    function claimLostAuctionStake(address _auctionId) public {
        require(lostAuctionStake[_auctionId][msg.sender] > 0, "Sender is a fraud");

        uint256 _prizeAmount = lostAuctionStake[_auctionId][msg.sender];
        delete (lostAuctionStake[_auctionId][msg.sender]);

        // TODO! Transfer this amount to the auction Loser
    }
}
