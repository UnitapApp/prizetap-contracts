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
        address[] participants;
        uint256 participantsCount;
        uint32 winnersCount;
        address[] winners;
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
        uint32 winnersCount,
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
        require(
            raffles[_raffleId].startTime < block.timestamp,
            "Raffle is not started"
        );
        require(
            raffles[_raffleId].endTime >= block.timestamp,
            "Raffle time is up"
        );
        uint256 participantsLength = _participants.length;
        require(participantsLength == _multipliers.length, "Length mismatch");
        require(
            participantsLength > 0 && participantsLength <= 100,
            "Invalid length"
        );
        require(
            raffles[_raffleId].participantsCount + participantsLength <=
                raffles[_raffleId].maxParticipants,
            "The maximum number of participants has been reached"
        );
        address[] storage participants = raffles[_raffleId].participants;
        raffles[_raffleId].participantsCount += participantsLength;

        for (uint256 i = 0; i < participantsLength; i++) {
            uint256 multiplier = _multipliers[i];
            address participant = _participants[i];

            require(
                !isParticipated[participant][_raffleId],
                "Already participated"
            );
            isParticipated[participant][_raffleId] = true;

            require(
                raffles[_raffleId].maxMultiplier >= multiplier &&
                    multiplier > 0,
                "Invalid multiplier"
            );
            for (uint256 j = 0; j < multiplier; j++) {
                participants.push(participant);
                participantPositions[_raffleId][participant].push(
                    participants.length
                );
            }
        }
    }

    function claimPrize(uint256 raffleId) external override {}

    function refundPrize(uint256 raffleId) external override {}

    function getParticipants(
        uint256 raffleId
    ) external view override returns (address[] memory) {
        Raffle memory raffle = raffles[raffleId];
        return raffle.participants;
    }

    function getWinners(
        uint256 raffleId
    ) external view returns (address[] memory) {
        Raffle memory raffle = raffles[raffleId];
        return raffle.winners;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return _ERC721_RECEIVED;
    }

    function drawRaffle(
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
        uint32 numWinners = raffles[raffleId].winnersCount;
        require(
            randomNumbers.length == numWinners,
            "Invalid number of random words"
        );
        require(
            block.timestamp <= expirationTime,
            "The random numbers have expired"
        );

        verifyRandomNumberSig(
            expirationTime,
            randomNumbers,
            reqId,
            signature,
            gatewaySignature
        );

        address[] storage participants = raffles[raffleId].participants;
        uint256 participantsLength = participants.length;

        address[] storage winners = raffles[raffleId].winners;
        for (uint32 i = 0; i < numWinners; i++) {
            if (participantsLength == 0) {
                break;
            }
            uint256 indexOfWinner = randomNumbers[i] % participantsLength;
            address winner = participants[indexOfWinner];
            winners.push(winner);
            isWinner[raffleId][winner] = true;
            participantsLength = moveWinnerToEnd(
                raffleId,
                winner,
                participantsLength
            );
        }

        raffles[raffleId].status = Status.CLOSED;

        emit WinnersSpecified(raffleId, raffles[raffleId].winners);
    }

    function moveWinnerToEnd(
        uint256 raffleId,
        address winner,
        uint256 participantsLength
    ) internal returns (uint256) {
        address[] storage participants = raffles[raffleId].participants;
        for (
            uint256 j = 0;
            j < participantPositions[raffleId][winner].length;
            j++
        ) {
            uint256 winnerIndex = participantPositions[raffleId][winner][j] - 1;
            uint256 lastIndex = participantsLength - 1;
            address lastParticipant = participants[lastIndex];
            if (winner != lastParticipant) {
                participants[winnerIndex] = lastParticipant;
                participants[lastIndex] = winner;
                exchangePositions(
                    raffleId,
                    winner,
                    lastParticipant,
                    winnerIndex + 1,
                    lastIndex + 1
                );
            }
            participantsLength--;
        }
        return participantsLength;
    }
}
