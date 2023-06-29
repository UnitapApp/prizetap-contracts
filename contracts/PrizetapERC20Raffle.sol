// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AbstractPrizetapRaffle.sol";

contract PrizetapERC20Raffle is AbstractPrizetapRaffle {
    struct Raffle {
        address initiator;
        uint256 prizeAmount;
        address currency; // Use null address for native currency
        uint256 maxParticipants;
        uint256 endTime;
        address[] participants;
        address winner; // Winner = address(0) means raffle is not held yet
        bool exists;
        Status status;
    }

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

    constructor(
        address _ChainlinkVRFCoordinator,
        uint64 _ChainlinkVRFSubscriptionId,
        bytes32 _ChainlinkKeyHash,
        address operator
    )
        AbstractPrizetapRaffle(
            _ChainlinkVRFCoordinator,
            _ChainlinkVRFSubscriptionId,
            _ChainlinkKeyHash,
            operator
        )
    {}

    function createRaffle(
        uint256 amount,
        address currency,
        uint256 maxParticipants,
        uint256 endTime
    ) external payable {
        require(amount > 0, "amount <= 0");
        require(maxParticipants > 0, "maxParticipants <= 0");
        require(endTime > block.timestamp, "endTime <= now");

        if (currency == address(0)) {
            require(msg.value == amount, "!msg.value");
        } else {
            IERC20 token = IERC20(currency);
            token.transferFrom(msg.sender, address(this), amount);
        }

        uint256 raffleId = ++lastRaffleId;

        Raffle storage raffle = raffles[raffleId];

        raffle.initiator = msg.sender;
        raffle.prizeAmount = amount;
        raffle.currency = currency;
        raffle.maxParticipants = maxParticipants;
        raffle.endTime = endTime;
        raffle.exists = true;
    }

    function participateInRaffle(
        uint256 raffleId,
        uint32 nonce,
        bytes memory signature
    ) external override whenNotPaused isOpenRaffle(raffleId) {
        require(
            raffles[raffleId].endTime >= block.timestamp,
            "Raffle time is up"
        );
        require(
            raffles[raffleId].participants.length <
                raffles[raffleId].maxParticipants,
            "The maximum number of participants has been reached"
        );
        bytes memory encodedData = abi.encodePacked(
            msg.sender,
            raffleId,
            nonce
        );
        _verifySignature(encodedData, signature);
        _verifyNonce(nonce);

        raffles[raffleId].participants.push(msg.sender);
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
    {
        require(
            raffles[raffleId].endTime < block.timestamp,
            "The raffle time has not ended"
        );
        raffles[raffleId].status = Status.CLOSED;
        requestRandomWords(raffleId);
    }

    function drawRaffle(
        uint256 raffleId,
        uint256[] memory randomWords
    ) internal override {
        require(
            raffles[raffleId].participants.length > 0,
            "There is no participant in raffle"
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
        address currency = raffles[raffleId].currency;

        if (currency == address(0)) {
            payable(msg.sender).transfer(raffles[raffleId].prizeAmount);
        } else {
            IERC20(currency).transfer(
                msg.sender,
                raffles[raffleId].prizeAmount
            );
        }
    }

    function getParticipants(
        uint256 raffleId
    ) public view override returns (address[] memory) {
        Raffle memory raffle = raffles[raffleId];
        return raffle.participants;
    }
}
