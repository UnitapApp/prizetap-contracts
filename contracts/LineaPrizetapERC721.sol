// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AbstractPrizetapRaffle.sol";

contract LineaPrizetapERC721 is AbstractPrizetapRaffle, IERC721Receiver {
    struct Raffle {
        address initiator;
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

    bytes4 public constant _ERC721_RECEIVED = 0x150b7a02;

    // raffleId => Raffle
    mapping(uint256 => Raffle) public raffles;

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
        uint256 maxParticipants,
        uint256 maxMultiplier,
        uint256 startTime,
        uint256 endTime,
        uint256 winnersCount,
        bytes32 requirementsHash
    ) external {
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

        uint256 raffleId = ++lastRaffleId;

        Raffle storage raffle = raffles[raffleId];

        raffle.initiator = msg.sender;
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
    ) external override {}

    function addParticipants(
        uint256 _raffleId,
        address[] calldata _participants,
        uint256[] calldata _multipliers
    ) external isOpenRaffle(_raffleId) onlyOperatorOrAdmin {
        Raffle storage raffle = raffles[_raffleId];
        require(raffle.startTime < block.timestamp, "Raffle is not started");
        require(raffle.endTime >= block.timestamp, "Raffle time is up");
        uint256 participantsLength = _participants.length;
        require(participantsLength == _multipliers.length, "Length mismatch");
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
            uint256 multiplier = _multipliers[i];
            address participant = _participants[i];

            require(
                !isParticipated[participant][_raffleId],
                "Already participated"
            );
            isParticipated[participant][_raffleId] = true;

            require(
                raffle.maxMultiplier >= multiplier && multiplier > 0,
                "Invalid multiplier"
            );
            for (uint256 j = 0; j < multiplier; j++) {
                raffle.lastParticipantIndex++;
                participantPositions[_raffleId][participant].push(
                    raffle.lastParticipantIndex
                );
                raffleParticipants[_raffleId][
                    raffle.lastParticipantIndex
                ] = participant;
            }
        }
        lastNotWinnerIndexes[_raffleId] = raffle.lastParticipantIndex;
    }

    function claimPrize(uint256 raffleId) external override {}

    function refundPrize(uint256 raffleId) external override {}

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

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return _ERC721_RECEIVED;
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

    function getWinnersCount(
        uint256 raffleId
    ) external view override returns (uint256 winnersCount) {
        winnersCount = raffles[raffleId].winnersCount;
    }
}
