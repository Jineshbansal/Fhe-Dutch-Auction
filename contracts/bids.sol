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

        counter = TFHE.asEuint256(69);
        TFHE.allowThis(counter);
    }

    struct Auction {
        string auctionTitle;
        address auctionId;
        string tokenName;
        uint256 tokenCount;
        uint256 minCount;
        uint256 startingBidTime;
        uint256 endTime;
    }

    struct Bid {
        string auctionTitle;
        address auctionId;
        address bidId;
        uint64 perTokenRate;
        uint64 tokenCount;
    }

    mapping(address => mapping(address => Bid)) public bids; // drop after revealAuction for _auctionId           --
    mapping(address => Auction) public auctions; // drop after revealAuction for _auctionId           --
    mapping(address => address[]) public auctionBidders; // drop after revealAuction for _auctionId           --
    Auction[] public allAuctions; // drop after claimLeftAuctionStake for _auctionId   --
    Bid[] public allBids; // for testing purposes                              --
    mapping(address => Bid[]) winningBids; // drop in claimLeftAuctionStake by bidId            --
    mapping(address => uint256) leftAuctionStake; // drop one by one in claimLeftAuctionStake          --
    mapping(address => mapping(address => uint256)) wonAuctionPrize; // drop in claimWonAuctionPrize --
    mapping(address => mapping(address => uint256)) lostAuctionStake; // drop in claimLostAuctionStake --
    mapping(address => Bid[]) myBids; // drop in claimWonAuctionPrize and claimLostAuctionPrize --

    // -------------TESTING---------------

    euint256 public counter;
    uint256 public counter_anon = 1;

    function increment() public {
        counter = TFHE.add(counter, TFHE.asEuint256(1));
        TFHE.allowThis(counter);
    }

    function getCounter() public {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(counter);
        Gateway.requestDecryption(cts, this.callbackCounter.selector, 0, block.timestamp + 1, true);
    }

    function callbackCounter(uint256, uint256 decryptedInput) public onlyGateway {
        counter_anon = decryptedInput;
        counter_anon = 90;
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
        string calldata _auctionTitle,
        uint64 _tokenCount,
        uint256 _startingBid, // may be same as start time
        uint256 _endTime,
        einput _encryptedAmount,
        bytes calldata inputProof
    ) public {
        require(auctions[msg.sender].auctionId != msg.sender, "Auction already exists");

        Auction memory newAuction = Auction({
            auctionTitle: _auctionTitle,
            auctionId: msg.sender,
            tokenName: "Token1",
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

    // function initiateBid(
    //     einput _auctionId,
    //     bytes calldata _auctionIdproof,
    //     einput _tokenRate,
    //     bytes calldata _tokenRateproof,
    //     einput _tokenCount,
    //     bytes calldata _tokenCountproof
    // ) public {
    //     eaddress auctionId = TFHE.asEaddress(_auctionId, _auctionIdproof);
    //     euint64 tokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
    //     euint64 tokenCount = TFHE.asEuint64(_tokenCount, _tokenCountproof);
    //     eaddress bidderId = TFHE.asEaddress(msg.sender);

    //     TFHE.allowThis(auctionId);
    //     TFHE.allowThis(tokenRate);
    //     TFHE.allowThis(tokenCount);
    //     TFHE.allowThis(bidderId);

    //     initiateBidInternal(bidderId, auctionId, tokenRate, tokenCount);
    // }

    function initiateBid(
        einput _auctionId,
        bytes calldata _auctionIdproof,
        einput _tokenRate,
        bytes calldata _tokenRateproof,
        einput _tokenCount,
        bytes calldata _tokenCountproof
    ) public {
        eaddress auctionId = TFHE.asEaddress(_auctionId, _auctionIdproof);
        euint64 tokenRate = TFHE.asEuint64(_tokenRate, _tokenRateproof);
        euint64 tokenCount = TFHE.asEuint64(_tokenCount, _tokenCountproof);
        eaddress bidderId = TFHE.asEaddress(msg.sender);

        TFHE.allowThis(auctionId);
        TFHE.allowThis(tokenRate);
        TFHE.allowThis(tokenCount);
        TFHE.allowThis(bidderId);

        // Decrypt all the params
        uint256[] memory cts = new uint256[](4);
        cts[0] = Gateway.toUint256(auctionId);
        cts[1] = Gateway.toUint256(tokenRate);
        cts[2] = Gateway.toUint256(tokenCount);
        cts[3] = Gateway.toUint256(bidderId);
        counter_anon = 900;
        Gateway.requestDecryption(cts, this.callbackInitiateBid.selector, 0, block.timestamp + 100, false);
    }

    function callbackInitiateBid(
        uint256,
        address _auctionId,
        uint64 _tokenRate,
        uint64 _tokenCount,
        address _bidderId
    ) public onlyGateway {
        
        Bid memory newBid = Bid({
            auctionTitle: "Jinesh",
            auctionId:0x37b2517Ce88D04095130FEB9E9E2725EC843Dc05 ,
            bidId:0x37b2517Ce88D04095130FEB9E9E2725EC843Dc05,
            perTokenRate: 12,
            tokenCount: 2
        });
        myBids[_bidderId].push(newBid);
        require(myBids[_bidderId].length==1,"Something is golmaal");
        counter_anon = 9120;
        // Now carry out the whole process
        require(bids[_auctionId][_bidderId].bidId != _bidderId);
        Auction memory auction = auctions[_auctionId];
        require(_tokenCount > auction.minCount);
        // require(auction.startingBidTime < block.timestamp);

        
        // bids[_auctionId][msg.sender] = newBid;
        // auctionBidders[_auctionId].push(msg.sender);
        // allBids.push(newBid);
        

        // TODO! Transfer funds of the bid, new ERC20 Token2
    }

    function revealAuction(address _auctionId) public returns (Bid[] memory) {
        require((auctions[msg.sender].auctionId == msg.sender) && (auctions[msg.sender].endTime < block.timestamp));
        require(auctions[_auctionId].auctionId == msg.sender);
        require(auctions[_auctionId].endTime < block.timestamp);

        Bid[] memory relBids = getBidsForAuction(msg.sender);
        uint256 tokenCount = auctions[msg.sender].tokenCount;
        delete winningBids[_auctionId]; // Clear any previous entries

        for (uint256 i = 0; i < relBids.length; i++) {
            if (tokenCount > 0) {
                // Winning Bids
                if (tokenCount > relBids[i].tokenCount) {
                    winningBids[_auctionId].push(relBids[i]);
                    wonAuctionPrize[_auctionId][relBids[i].bidId] = relBids[i].tokenCount;
                    tokenCount -= relBids[i].tokenCount;
                } else {
                    // Partial Win
                    winningBids[_auctionId].push(relBids[i]);
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

        return winningBids[_auctionId];
    }

    // By the Bid winner
    function claimWonAuctionPrize(address _auctionId) public {
        require(wonAuctionPrize[_auctionId][msg.sender] > 0, "Sender is a fraud");

        uint256 _prizeAmount = wonAuctionPrize[_auctionId][msg.sender];
        delete (wonAuctionPrize[_auctionId][msg.sender]);

        for (uint256 i = 0; i < myBids[msg.sender].length; i++) {
            if (myBids[msg.sender][i].auctionId == _auctionId) {
                myBids[msg.sender][i] = myBids[msg.sender][myBids[msg.sender].length - 1];
                myBids[msg.sender].pop();
                break;
            }
        }

        // TODO! Transfer this amount to the auction Winner
    }

    // By the auction owner
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

    // By the bid loser
    function claimLostAuctionStake(address _auctionId) public {
        require(lostAuctionStake[_auctionId][msg.sender] > 0, "Sender is a fraud");

        uint256 _prizeAmount = lostAuctionStake[_auctionId][msg.sender];
        delete (lostAuctionStake[_auctionId][msg.sender]);

        for (uint256 i = 0; i < myBids[msg.sender].length; i++) {
            if (myBids[msg.sender][i].auctionId == _auctionId) {
                myBids[msg.sender][i] = myBids[msg.sender][myBids[msg.sender].length - 1];
                myBids[msg.sender].pop();
                break;
            }
        }

        // TODO! Transfer this amount to the auction Loser
    }
}
