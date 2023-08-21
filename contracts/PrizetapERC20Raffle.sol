// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AbstractPrizetapRaffle.sol";

contract PrizetapERC20Raffle is AbstractPrizetapRaffle {
    using SafeERC20 for IERC20;

    struct Raffle {
        address initiator;
        uint256 prizeAmount;
        address currency; // Use null address for native currency
        uint256 maxParticipants;
        uint256 maxMultiplier;
        uint256 startTime;
        uint256 endTime;
        address[] participants;
        uint256 participantsCount;
        address winner; // Winner = address(0) means raffle is not held yet
        bool exists;
        Status status;
        bytes32 requirementsHash;
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
        address _chainlinkVRFCoordinator,
        uint64 _chainlinkVRFSubscriptionId,
        bytes32 _chainlinkKeyHash,
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muon,
        address _admin,
        address _operator
    )
        AbstractPrizetapRaffle(
            _chainlinkVRFCoordinator,
            _chainlinkVRFSubscriptionId,
            _chainlinkKeyHash,
            _muonAppId,
            _muonPublicKey,
            _muon,
            _admin,
            _operator
        )
    {}

    function createRaffle(
        uint256 amount,
        address currency,
        uint256 maxParticipants,
        uint256 maxMultiplier,
        uint256 startTime,
        uint256 endTime,
        bytes32 requirementsHash
    ) external payable {
        require(amount > 0, "amount <= 0");
        require(maxParticipants > 0, "maxParticipants <= 0");
        require(maxMultiplier > 0, "maxMultiplier <= 0");
        require(
            startTime > block.timestamp + validationPeriod,
            "startTime <= now + validationPeriod"
        );
        require(endTime > startTime, "endTime <= startTime");

        if (currency == address(0)) {
            require(msg.value == amount, "!msg.value");
        } else {
            uint256 balance = IERC20(currency).balanceOf(address(this));

            IERC20(currency).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );

            uint256 receivedAmount = IERC20(currency).balanceOf(address(this)) -
                balance;

            require(amount == receivedAmount, "receivedAmount != amount");
        }

        uint256 raffleId = ++lastRaffleId;

        Raffle storage raffle = raffles[raffleId];

        raffle.initiator = msg.sender;
        raffle.prizeAmount = amount;
        raffle.currency = currency;
        raffle.maxParticipants = maxParticipants;
        raffle.maxMultiplier = maxMultiplier;
        raffle.startTime = startTime;
        raffle.endTime = endTime;
        raffle.exists = true;
        raffle.requirementsHash = requirementsHash;

        emit RaffleCreated(msg.sender, raffleId);
    }

    function rejectRaffle(
        uint256 raffleId
    ) external override onlyOperatorOrAdmin isOpenRaffle(raffleId) {
        require(
            raffles[raffleId].participantsCount == 0,
            "Raffle's participants count > 0"
        );
        raffles[raffleId].status = Status.REJECTED;

        emit RaffleRejected(raffleId, msg.sender);
    }

    function participateInRaffle(
        uint256 raffleId,
        uint256 multiplier,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature
    )
        external
        override
        whenNotPaused
        isOpenRaffle(raffleId)
        checkParticipated(raffleId)
    {
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

        verifyTSS(raffleId, multiplier, reqId, signature);

        raffles[raffleId].participantsCount += 1;

        for (uint256 i = 0; i < multiplier; i++) {
            raffles[raffleId].participants.push(msg.sender);
        }

        emit Participate(msg.sender, raffleId, multiplier);
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

        emit RaffleHeld(raffleId, msg.sender);
    }

    function claimPrize(
        uint256 raffleId
    ) external override whenNotPaused onlyWinner(raffleId) {
        raffles[raffleId].status = Status.CLAIMED;
        address currency = raffles[raffleId].currency;

        if (currency == address(0)) {
            payable(msg.sender).transfer(raffles[raffleId].prizeAmount);
        } else {
            IERC20(currency).safeTransfer(
                msg.sender,
                raffles[raffleId].prizeAmount
            );
        }

        emit PrizeClaimed(raffleId, msg.sender);
    }

    function refundPrize(uint256 raffleId) external override whenNotPaused {
        require(raffles[raffleId].participants.length == 0, "participants > 0");
        require(
            raffles[raffleId].status == Status.REJECTED ||
                raffles[raffleId].endTime < block.timestamp,
            "The raffle is not rejected"
        );
        require(
            msg.sender == raffles[raffleId].initiator,
            "Permission denied!"
        );

        raffles[raffleId].status = Status.REFUNDED;

        address currency = raffles[raffleId].currency;

        if (currency == address(0)) {
            payable(msg.sender).transfer(raffles[raffleId].prizeAmount);
        } else {
            IERC20(currency).safeTransfer(
                msg.sender,
                raffles[raffleId].prizeAmount
            );
        }

        emit PrizeRefunded(raffleId);
    }

    function getParticipants(
        uint256 raffleId
    ) external view override returns (address[] memory) {
        Raffle memory raffle = raffles[raffleId];
        return raffle.participants;
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

        emit WinnerSpecified(raffleId, raffles[raffleId].winner);
    }
}
