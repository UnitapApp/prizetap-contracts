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
        uint256 lastParticipantIndex;
        uint256 lastWinnerIndex;
        uint256 participantsCount;
        uint256 winnersCount;
        uint256[] randomNumbers;
        bool exists;
        Status status;
        bytes32 requirementsHash;
    }

    // raffleId => Raffle
    mapping(uint256 => Raffle) public raffles;

    modifier onlyWinner(uint256 raffleId) override {
        require(raffles[raffleId].exists, "The raffle does not exist");
        require(isWinner[raffleId][msg.sender], "You are not winner!");
        require(
            !isWinnerClaimed[raffleId][msg.sender],
            "You already claimed the prize!"
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
            raffles[raffleId].participantsCount > 0,
            "There is no participant in raffle"
        );
        require(
            raffles[raffleId].endTime < block.timestamp,
            "The raffle time has not ended"
        );
        _;
    }

    constructor(
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muon,
        address _muonValidGateway,
        address _admin,
        address _operator
    )
        AbstractPrizetapRaffle(
            _muonAppId,
            _muonPublicKey,
            _muon,
            _muonValidGateway,
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
        uint256 winnersCount,
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
        require(
            winnersCount > 0 &&
                winnersCount <= MAX_NUM_WINNERS &&
                winnersCount <= maxParticipants,
            "Invalid winnersCount"
        );

        uint256 totalPrizeAmount = amount * winnersCount;

        if (currency == address(0)) {
            require(msg.value == totalPrizeAmount, "!msg.value");
        } else {
            uint256 balance = IERC20(currency).balanceOf(address(this));

            IERC20(currency).safeTransferFrom(
                msg.sender,
                address(this),
                totalPrizeAmount
            );

            uint256 receivedAmount = IERC20(currency).balanceOf(address(this)) -
                balance;

            require(
                totalPrizeAmount == receivedAmount,
                "receivedAmount != amount"
            );
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
        raffle.winnersCount = winnersCount;
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
        IMuonClient.SchnorrSign calldata signature,
        bytes calldata gatewaySignature
    )
        external
        override
        whenNotPaused
        isOpenRaffle(raffleId)
        checkParticipated(raffleId)
    {
        Raffle storage raffle = raffles[raffleId];
        require(raffle.startTime < block.timestamp, "Raffle is not started");
        require(raffle.endTime >= block.timestamp, "Raffle time is up");
        require(
            raffle.participantsCount < raffle.maxParticipants,
            "The maximum number of participants has been reached"
        );
        require(
            raffle.maxMultiplier >= multiplier && multiplier > 0,
            "Invalid multiplier"
        );

        verifyParticipationSig(
            raffleId,
            multiplier,
            reqId,
            signature,
            gatewaySignature
        );

        raffle.participantsCount += 1;

        for (uint256 i = 0; i < multiplier; i++) {
            raffle.lastParticipantIndex++;
            participantPositions[raffleId][msg.sender].push(
                raffle.lastParticipantIndex
            );
            raffleParticipants[raffleId][raffle.lastParticipantIndex] = msg
                .sender;
        }
        lastNotWinnerIndexes[raffleId] = raffle.lastParticipantIndex;

        emit Participate(msg.sender, raffleId, multiplier);
    }

    function batchParticipate(
        uint256 raffleId,
        address[] calldata participants,
        uint256[] calldata multipliers
    ) external isOpenRaffle(raffleId) onlyOperatorOrAdmin {
        Raffle storage raffle = raffles[raffleId];
        require(raffle.startTime < block.timestamp, "Raffle is not started");
        require(raffle.endTime >= block.timestamp, "Raffle time is up");
        uint256 participantsLength = participants.length;
        require(participantsLength == multipliers.length, "Mismatched lengths");
        require(
            participantsLength > 0 && participantsLength <= 100,
            "Invalid length"
        );
        require(
            raffle.participantsCount + participantsLength <=
                raffle.maxParticipants,
            "The maximum number of participants has been reached"
        );

        raffle.participantsCount += participantsLength;

        for (uint256 i = 0; i < participantsLength; i++) {
            uint256 multiplier = multipliers[i];
            address participant = participants[i];

            require(
                !isParticipated[participant][raffleId],
                "Already participated"
            );
            isParticipated[participant][raffleId] = true;

            require(
                raffle.maxMultiplier >= multiplier && multiplier > 0,
                "Invalid multiplier"
            );
            for (uint256 j = 0; j < multiplier; j++) {
                raffle.lastParticipantIndex++;
                participantPositions[raffleId][participant].push(
                    raffle.lastParticipantIndex
                );
                raffleParticipants[raffleId][
                    raffle.lastParticipantIndex
                ] = participant;
            }

            emit Participate(participant, raffleId, multiplier);
        }
        lastNotWinnerIndexes[raffleId] = raffle.lastParticipantIndex;
    }

    function claimPrize(
        uint256 raffleId
    ) external override whenNotPaused onlyWinner(raffleId) {
        isWinnerClaimed[raffleId][msg.sender] = true;
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
        require(raffles[raffleId].participantsCount == 0, "participants > 0");
        require(
            raffles[raffleId].status == Status.REJECTED ||
                raffles[raffleId].endTime < block.timestamp,
            "The raffle is not rejected or expired"
        );
        require(
            raffles[raffleId].status != Status.REFUNDED,
            "The raffle is already refunded"
        );
        require(
            msg.sender == raffles[raffleId].initiator,
            "Permission denied!"
        );

        raffles[raffleId].status = Status.REFUNDED;

        address currency = raffles[raffleId].currency;
        uint256 totalPrizeAmount = raffles[raffleId].prizeAmount *
            raffles[raffleId].winnersCount;

        if (currency == address(0)) {
            payable(msg.sender).transfer(totalPrizeAmount);
        } else {
            IERC20(currency).safeTransfer(msg.sender, totalPrizeAmount);
        }

        emit PrizeRefunded(raffleId);
    }

    function refundRemainingPrizes(uint256 raffleId) external whenNotPaused {
        Raffle storage raffle = raffles[raffleId];
        require(
            raffle.participantsCount < raffle.winnersCount,
            "participants > winners"
        );
        require(raffle.status == Status.CLOSED, "The raffle is not closed");
        require(msg.sender == raffle.initiator, "Permission denied!");

        raffle.status = Status.REFUNDED;

        address currency = raffle.currency;
        uint256 totalPrizeAmount = raffle.prizeAmount *
            (raffle.winnersCount - raffle.participantsCount);

        if (currency == address(0)) {
            payable(msg.sender).transfer(totalPrizeAmount);
        } else {
            IERC20(currency).safeTransfer(msg.sender, totalPrizeAmount);
        }

        emit PrizeRefunded(raffleId);
    }

    function getParticipants(
        uint256 raffleId,
        uint256 fromId,
        uint256 toId
    ) external view override returns (address[] memory participants) {
        fromId = fromId > 0 ? fromId : 1;
        toId = toId <= raffles[raffleId].lastParticipantIndex
            ? toId
            : raffles[raffleId].lastParticipantIndex;
        require(fromId <= toId, "Invalid range!");

        participants = new address[](toId - fromId + 1);

        uint256 j = 0;
        for (uint256 i = fromId; i <= toId; i++) {
            participants[j++] = raffleParticipants[raffleId][i];
        }

        // Resize the array to remove any unused elements
        assembly {
            mstore(participants, j)
        }
    }

    function getWinners(
        uint256 raffleId,
        uint256 fromId,
        uint256 toId
    ) external view override returns (address[] memory winners) {
        fromId = fromId > 0 ? fromId : 1;
        toId = toId <= raffles[raffleId].lastWinnerIndex
            ? toId
            : raffles[raffleId].lastWinnerIndex;
        require(fromId <= toId, "Invalid range!");

        winners = new address[](toId - fromId + 1);

        uint256 j = 0;
        for (uint256 i = fromId; i <= toId; i++) {
            winners[j++] = raffleWinners[raffleId][i];
        }

        // Resize the array to remove any unused elements
        assembly {
            mstore(winners, j)
        }
    }

    function setRaffleRandomNumbers(
        uint256 raffleId,
        uint256 expirationTime,
        uint256[] calldata randomNumbers,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature,
        bytes calldata gatewaySignature
    )
        external
        override
        whenNotPaused
        isOpenRaffle(raffleId)
        hasEnded(raffleId)
    {
        require(
            randomNumbers.length == raffles[raffleId].winnersCount,
            "Invalid number of random words"
        );
        require(
            block.timestamp <= expirationTime,
            "The random numbers have expired"
        );
        require(
            raffles[raffleId].randomNumbers.length == 0,
            "The random numbers are already set"
        );

        verifyRandomNumberSig(
            expirationTime,
            randomNumbers,
            reqId,
            signature,
            gatewaySignature
        );
        raffles[raffleId].randomNumbers = randomNumbers;
    }

    function setWinners(
        uint256 raffleId,
        uint256 toId
    )
        external
        override
        whenNotPaused
        isOpenRaffle(raffleId)
        hasEnded(raffleId)
    {
        Raffle storage raffle = raffles[raffleId];
        uint256[] memory randomNumbers = raffle.randomNumbers;

        require(randomNumbers.length > 0, "Random numbers are not set");
        require(
            toId > raffle.lastWinnerIndex && toId <= raffle.winnersCount,
            "Invalid toId"
        );

        uint256 participantsLength = lastNotWinnerIndexes[raffleId];
        uint256 fromId = raffle.lastWinnerIndex + 1;
        for (uint256 i = fromId; i <= toId; i++) {
            if (participantsLength == 0) {
                break;
            }
            uint256 indexOfWinner = (randomNumbers[i - 1] %
                participantsLength) + 1;
            address winner = raffleParticipants[raffleId][indexOfWinner];
            raffleWinners[raffleId][i] = winner;
            isWinner[raffleId][winner] = true;
            participantsLength = moveWinnerToEnd(
                raffleId,
                winner,
                participantsLength
            );
        }
        lastNotWinnerIndexes[raffleId] = participantsLength;
        raffle.lastWinnerIndex = toId;
        if (toId == raffle.winnersCount) {
            raffles[raffleId].status = Status.CLOSED;
        }

        emit WinnersSpecified(raffleId, fromId, toId);
    }

    function adminWithdraw(
        uint256 _amount,
        address _to,
        address _tokenAddr
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to != address(0), "Invalid recipient");
        if (_tokenAddr == address(0)) {
            payable(_to).transfer(_amount);
        } else {
            IERC20(_tokenAddr).transfer(_to, _amount);
        }
    }

    function getWinnersCount(
        uint256 raffleId
    ) external view override returns (uint256 winnersCount) {
        winnersCount = raffles[raffleId].winnersCount;
    }
}
