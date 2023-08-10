// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AbstractPrizetapRaffle.sol";

contract PrizetapERC721Raffle is AbstractPrizetapRaffle, IERC721Receiver {
    struct Raffle {
        address initiator;
        address collection;
        uint256 tokenId;
        uint256 maxParticipants;
        uint256 maxMultiplier;
        uint256 startTime;
        uint256 endTime;
        address[] participants;
        uint256 participantsCount;
        address winner; // Winner = address(0) means raffle is not held yet
        bool exists;
        Status status;
    }

    bytes4 public constant _ERC721_RECEIVED = 0x150b7a02;

    mapping(uint256 => Raffle) public raffles;

    modifier onlyWinner(uint256 raffleId) override {
        require(raffles[raffleId].exists, "The raffle does not exist");
        require(
            raffles[raffleId].status == Status.HELD &&
                msg.sender == raffles[raffleId].winner,
            "Permission denied"
        );
        _;
    }

    modifier isOpenRaffle(uint256 raffleId) {
        require(raffles[raffleId].exists, "The raffle does not exist");
        require(
            raffles[raffleId].status == Status.OPEN,
            "The raffle is not open"
        );
        _;
    }

    modifier hasEnded(uint256 raffleId) {
        require(
            raffles[raffleId].participants.length > 0,
            "There is no participant in raffle"
        );
        require(
            raffles[raffleId].endTime < block.timestamp,
            "The raffle time has not ended"
        );
        _;
    }

    constructor(
        address _ChainlinkVRFCoordinator,
        uint64 _ChainlinkVRFSubscriptionId,
        bytes32 _ChainlinkKeyHash,
        address admin,
        address operator
    )
        AbstractPrizetapRaffle(
            _ChainlinkVRFCoordinator,
            _ChainlinkVRFSubscriptionId,
            _ChainlinkKeyHash,
            admin,
            operator
        )
    {}

    function createRaffle(
        address collection,
        uint256 tokenId,
        uint256 maxParticipants,
        uint256 maxMultiplier,
        uint256 startTime,
        uint256 endTime
    ) external payable {
        require(maxParticipants > 0, "maxParticipants <= 0");
        require(maxMultiplier > 0, "maxMultiplier <= 0");
        require(
            startTime > block.timestamp + validationPeriod,
            "startTime <= now + validationPeriod"
        );
        require(endTime > startTime, "endTime <= startTime");

        IERC721(collection).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        require(
            IERC721(collection).ownerOf(tokenId) == address(this),
            "Not received the NFT"
        );

        uint256 raffleId = ++lastRaffleId;

        Raffle storage raffle = raffles[raffleId];

        raffle.initiator = msg.sender;
        raffle.collection = collection;
        raffle.tokenId = tokenId;
        raffle.maxParticipants = maxParticipants;
        raffle.maxMultiplier = maxMultiplier;
        raffle.startTime = startTime;
        raffle.endTime = endTime;
        raffle.exists = true;
    }

    function rejectRaffle(
        uint256 raffleId
    ) external override onlyOperatorOrAdmin isOpenRaffle(raffleId) {
        require(
            raffles[raffleId].participantsCount == 0,
            "Raffle's participants count > 0"
        );
        raffles[raffleId].status = Status.REJECTED;
    }

    function participateInRaffle(
        uint256 raffleId,
        uint32 nonce,
        bytes memory signature,
        uint256 multiplier
    ) external override whenNotPaused isOpenRaffle(raffleId) {
        require(
            raffles[raffleId].startTime < block.timestamp,
            "Raffle is not started"
        );
        require(
            raffles[raffleId].endTime >= block.timestamp,
            "Raffle time is up"
        );
        require(
            raffles[raffleId].participantsCount <
                raffles[raffleId].maxParticipants,
            "The maximum number of participants has been reached"
        );
        require(
            raffles[raffleId].maxMultiplier >= multiplier,
            "Invalid multiplier"
        );
        bytes memory encodedData = abi.encodePacked(
            msg.sender,
            raffleId,
            nonce,
            multiplier
        );
        _verifySignature(encodedData, signature);
        _verifyNonce(nonce);

        raffles[raffleId].participantsCount += 1;

        for (uint256 i = 0; i < multiplier; i++) {
            raffles[raffleId].participants.push(msg.sender);
        }

        emit Participate(msg.sender, raffleId);
    }

    function heldRaffle(
        uint256 raffleId
    )
        external
        override
        whenNotPaused
        onlyOperatorOrAdmin
        isOpenRaffle(raffleId)
        hasEnded(raffleId)
    {
        raffles[raffleId].status = Status.CLOSED;
        requestRandomWords(raffleId);
    }

    function drawRaffle(
        uint256 raffleId,
        uint256[] memory randomWords
    ) internal override hasEnded(raffleId) {
        require(
            raffles[raffleId].status == Status.CLOSED,
            "The raffle is not closed"
        );
        uint256 indexOfWinner = randomWords[0] %
            raffles[raffleId].participants.length;

        raffles[raffleId].status = Status.HELD;
        raffles[raffleId].winner = raffles[raffleId].participants[
            indexOfWinner
        ];
    }

    function claimPrize(
        uint256 raffleId,
        bytes memory signature
    ) external override whenNotPaused onlyWinner(raffleId) {
        bytes memory encodedData = abi.encodePacked(msg.sender, raffleId);
        _verifySignature(encodedData, signature);

        raffles[raffleId].status = Status.CLAIMED;

        IERC721(raffles[raffleId].collection).safeTransferFrom(
            address(this),
            msg.sender,
            raffles[raffleId].tokenId
        );
    }

    function refundPrize(uint256 raffleId) external override whenNotPaused {
        require(raffles[raffleId].participants.length == 0, "participants > 0");
        require(
            raffles[raffleId].status == Status.REJECTED,
            "The raffle is not rejected"
        );
        require(
            msg.sender == raffles[raffleId].initiator,
            "Permission denied!"
        );

        raffles[raffleId].status = Status.REFUNDED;

        IERC721(raffles[raffleId].collection).safeTransferFrom(
            address(this),
            msg.sender,
            raffles[raffleId].tokenId
        );
    }

    function getParticipants(
        uint256 raffleId
    ) public view override returns (address[] memory) {
        Raffle memory raffle = raffles[raffleId];
        return raffle.participants;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return _ERC721_RECEIVED;
    }
}
