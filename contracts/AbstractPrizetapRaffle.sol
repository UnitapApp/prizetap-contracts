// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "./IMuonClient.sol";

abstract contract AbstractPrizetapRaffle is
    AccessControl,
    Pausable,
    VRFConsumerBaseV2
{
    enum Status {
        OPEN,
        CLOSED,
        HELD,
        CLAIMED,
        REJECTED,
        REFUNDED
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(uint256 => uint256) public vrfRequests; // Map vrfRequestId to raffleId

    // Check if the wallet has already participated in the raffle
    // wallet => (raffleId => bool)
    mapping(address => mapping(uint256 => bool)) public isParticipated;

    uint256 public lastRaffleId = 0;

    uint256 public validationPeriod = 7 days;

    uint256 public muonAppId;

    IMuonClient.PublicKey public muonPublicKey;

    IMuonClient public muon;

    uint64 chainlinkVrfSubscriptionId;

    bytes32 chainlinkKeyHash;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 100000;

    uint16 vrfRequestConfirmations = 3;

    VRFCoordinatorV2Interface private immutable CHAINLINK_VRF_COORDINATOR;

    event VRFRequestSent(uint256 requestId);
    event VRFRequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Participate(
        address indexed user,
        uint256 raffleId,
        uint256 multiplier
    );
    event RaffleCreated(address indexed initiator, uint256 raffleId);
    event RaffleRejected(uint256 indexed raffleId, address indexed rejector);
    event RaffleHeld(uint256 indexed raffleId, address indexed organizer);
    event WinnerSpecified(uint256 indexed raffleId, address indexed winner);
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

    constructor(
        address _chainlinkVRFCoordinator,
        uint64 _chainlinkVRFSubscriptionId,
        bytes32 _chainlinkKeyHash,
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muon,
        address _admin,
        address _operator
    ) VRFConsumerBaseV2(_chainlinkVRFCoordinator) {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _operator);
        CHAINLINK_VRF_COORDINATOR = VRFCoordinatorV2Interface(
            _chainlinkVRFCoordinator
        );
        chainlinkVrfSubscriptionId = _chainlinkVRFSubscriptionId;
        chainlinkKeyHash = _chainlinkKeyHash;
        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
        muon = IMuonClient(_muon);
    }

    function setValidationPeriod(
        uint256 periodSeconds
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(periodSeconds > 0, "Invalid period");
        validationPeriod = periodSeconds;
    }

    function setCallbackGasLimit(
        uint32 gaslimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        callbackGasLimit = gaslimit;
    }

    function setVrfRequestConfirmations(
        uint16 count
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vrfRequestConfirmations = count;
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

    function rejectRaffle(uint256 raffleId) external virtual;

    function participateInRaffle(
        uint256 raffleId,
        uint256 multiplier,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata signature
    ) external virtual;

    function heldRaffle(uint256 raffleId) external virtual;

    function claimPrize(uint256 raffleId) external virtual;

    function refundPrize(uint256 raffleId) external virtual;

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getParticipants(
        uint256 raffleId
    ) external view virtual returns (address[] memory);

    function verifyTSS(
        uint256 raffleId,
        uint256 multiplier,
        bytes calldata reqId,
        IMuonClient.SchnorrSign calldata sign
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                muonAppId,
                reqId,
                block.chainid,
                msg.sender,
                raffleId,
                multiplier
            )
        );
        bool verified = muon.muonVerify(
            reqId,
            uint256(hash),
            sign,
            muonPublicKey
        );
        require(verified, "Invalid signature!");
    }

    function drawRaffle(
        uint256 raffleId,
        uint256[] memory randomWords
    ) internal virtual;

    function requestRandomWords(uint256 raffleId) internal {
        // Will revert if subscription is not set and funded.
        uint256 requestId = CHAINLINK_VRF_COORDINATOR.requestRandomWords(
            chainlinkKeyHash,
            chainlinkVrfSubscriptionId,
            vrfRequestConfirmations,
            callbackGasLimit,
            1
        );
        vrfRequests[requestId] = raffleId;
        emit VRFRequestSent(requestId);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(vrfRequests[_requestId] != 0, "VRF: Request not found");
        drawRaffle(vrfRequests[_requestId], _randomWords);
        emit VRFRequestFulfilled(_requestId, _randomWords);
    }
}
