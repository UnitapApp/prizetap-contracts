// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "./IMuonClient.sol";

abstract contract AbstractPrizetapRaffle is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using ECDSAUpgradeable for bytes32;

    enum Status {
        OPEN,
        CLOSED,
        REJECTED,
        REFUNDED
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant MAX_NUM_WINNERS = 500;

    // Check if the wallet has already participated in the raffle
    // wallet => (raffleId => bool)
    mapping(address => mapping(uint256 => bool)) public isParticipated;
    // raffleId => ( winner => isWinner )
    mapping(uint256 => mapping(address => bool)) public isWinner;
    // raffleId => ( winner => claimed )
    mapping(uint256 => mapping(address => bool)) public isWinnerClaimed;
    // raffleId => ( participant => positions[] )
    mapping(uint256 => mapping(address => uint256[]))
        public participantPositions;
    // raffleId => ( index+1 => address )
    mapping(uint256 => mapping(uint256 => address)) public raffleParticipants;
    // raffleId => ( index+1 => address )
    mapping(uint256 => mapping(uint256 => address)) public raffleWinners;
    // raffleId => lastNotWinnerIndex
    mapping(uint256 => uint256) public lastNotWinnerIndexes;

    uint256 public lastRaffleId;

    uint256 public validationPeriod;

    uint256 public muonAppId;

    IMuonClient.PublicKey public muonPublicKey;

    IMuonClient public muon;

    address public muonValidGateway;

    event Participate(
        address indexed user,
        uint256 raffleId,
        uint256 multiplier
    );
    event RaffleCreated(address indexed initiator, uint256 raffleId);
    event RaffleRejected(uint256 indexed raffleId, address indexed rejector);
    event WinnersSpecified(
        uint256 indexed raffleId,
        uint256 fromId,
        uint256 toId
    );
    event PrizeClaimed(uint256 indexed raffleId, address indexed winner);
    event PrizeRefunded(uint256 indexed raffleId);

    modifier onlyWinner(uint256 raffleId) virtual {
        _;
    }

    modifier onlyOperatorOrAdmin() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender) ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Permission denied!"
        );
        _;
    }

    modifier checkParticipated(uint256 raffleId) {
        require(!isParticipated[msg.sender][raffleId], "Already participated");
        isParticipated[msg.sender][raffleId] = true;
        _;
    }

    function __AbstractPrizetapRaffle_init(
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muon,
        address _muonValidGateway,
        address _admin,
        address _operator
    ) internal initializer {
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _operator);
        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
        muon = IMuonClient(_muon);
        muonValidGateway = _muonValidGateway;
    }

    function __AbstractPrizetapRaffle_init_unchained() internal initializer {}

    function setValidationPeriod(
        uint256 periodSeconds
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validationPeriod = periodSeconds;
    }

    function setMuonAppId(
        uint256 _muonAppId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        muonAppId = _muonAppId;
    }

    function setMuonPublicKey(
        IMuonClient.PublicKey memory _muonPublicKey
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        muonPublicKey = _muonPublicKey;
    }

    function setMuonAddress(
        address _muonAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        muon = IMuonClient(_muonAddress);
    }

    function setMuonGateway(
        address _gatewayAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        muonValidGateway = _gatewayAddress;
    }

    function rejectRaffle(uint256 raffleId) external virtual;

    function participateInRaffle(
        uint256 raffleId,
        uint256 multiplier,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature,
        bytes calldata gatewaySignature
    ) external virtual;

    function claimPrize(uint256 raffleId) external virtual;

    function refundPrize(uint256 raffleId) external virtual;

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getParticipants(
        uint256 raffleId,
        uint256 fromId,
        uint256 toId
    ) external view virtual returns (address[] memory);

    function getWinners(
        uint256 raffleId,
        uint256 fromId,
        uint256 toId
    ) external view virtual returns (address[] memory);

    function setRaffleRandomNumbers(
        uint256 raffleId,
        uint256 expirationTime,
        uint256[] calldata randomWords,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature,
        bytes calldata gatewaySignature
    ) external virtual;

    function setWinners(uint256 raffleId, uint256 toId) external virtual;

    function getWinnersCount(
        uint256 raffleId
    ) external view virtual returns (uint256);

    function verifyParticipationSig(
        uint256 raffleId,
        uint256 multiplier,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                muonAppId,
                reqId,
                block.chainid,
                address(this),
                msg.sender,
                raffleId,
                multiplier
            )
        );
        verifyMuonSig(reqId, hash, sign, gatewaySignature);
    }

    function verifyRandomNumberSig(
        uint256 expirationTime,
        uint256[] calldata randomNumbers,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(muonAppId, reqId, randomNumbers, expirationTime)
        );
        verifyMuonSig(reqId, hash, sign, gatewaySignature);
    }

    function verifyMuonSig(
        bytes calldata reqId,
        bytes32 hash,
        IMuonClient.SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) internal {
        bool verified = muon.muonVerify(
            reqId,
            uint256(hash),
            sign,
            muonPublicKey
        );
        require(verified, "Invalid signature!");

        hash = hash.toEthSignedMessageHash();
        address gatewaySignatureSigner = hash.recover(gatewaySignature);

        require(
            gatewaySignatureSigner == muonValidGateway,
            "Gateway is not valid"
        );
    }

    function moveWinnerToEnd(
        uint256 raffleId,
        address winner,
        uint256 participantsLength
    ) internal returns (uint256) {
        uint256 positionsLength = participantPositions[raffleId][winner].length;

        for (uint256 j = 0; j < positionsLength; j++) {
            uint256 winnerIndex = participantPositions[raffleId][winner][j];
            uint256 lastIndex = participantsLength;
            address lastParticipant = raffleParticipants[raffleId][lastIndex];
            raffleParticipants[raffleId][winnerIndex] = lastParticipant;
            raffleParticipants[raffleId][lastIndex] = winner;
            exchangePositions(
                raffleId,
                winner,
                lastParticipant,
                winnerIndex,
                lastIndex
            );
            participantsLength--;
        }
        return participantsLength;
    }

    function exchangePositions(
        uint256 raffleId,
        address user1,
        address user2,
        uint256 position1,
        uint256 position2
    ) internal {
        uint256[] storage user1Positions = participantPositions[raffleId][
            user1
        ];
        uint256 user1PositionsLength = user1Positions.length;
        uint256[] storage user2Positions = participantPositions[raffleId][
            user2
        ];
        uint256 user2PositionsLength = user2Positions.length;
        uint256 positionIndex1;
        uint256 positionIndex2;
        for (uint256 i = 0; i < user1PositionsLength; i++) {
            if (user1Positions[i] == position1) {
                positionIndex1 = i;
                break;
            }
        }
        for (uint256 j = 0; j < user2PositionsLength; j++) {
            if (user2Positions[j] == position2) {
                positionIndex2 = j;
                break;
            }
        }
        user1Positions[positionIndex1] = position2;
        user2Positions[positionIndex2] = position1;
    }
}
