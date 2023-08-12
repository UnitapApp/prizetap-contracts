// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "./MuonClient.sol";

abstract contract AbstractPrizetapRaffle is
    AccessControl,
    Pausable,
    VRFConsumerBaseV2,
    MuonClient
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

    mapping(address => mapping(uint32 => bool)) public usedNonces;

    uint256 public lastRaffleId = 0;

    uint256 public validationPeriod = 7 days;

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

    constructor(
        address _ChainlinkVRFCoordinator,
        uint64 _ChainlinkVRFSubscriptionId,
        bytes32 _ChainlinkKeyHash,
        uint256 _muonAppId,
        PublicKey memory _muonPublicKey,
        address admin,
        address operator
    )
        VRFConsumerBaseV2(_ChainlinkVRFCoordinator)
        MuonClient(_muonAppId, _muonPublicKey)
    {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(OPERATOR_ROLE, operator);
        CHAINLINK_VRF_COORDINATOR = VRFCoordinatorV2Interface(
            _ChainlinkVRFCoordinator
        );
        chainlinkVrfSubscriptionId = _ChainlinkVRFSubscriptionId;
        chainlinkKeyHash = _ChainlinkKeyHash;
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

    function rejectRaffle(uint256 raffleId) external virtual;

    function participateInRaffle(
        uint256 raffleId,
        uint32 nonce,
        uint256 multiplier,
        bytes calldata reqId,
        SchnorrSign calldata signature
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
        uint32 nonce,
        uint256 multiplier,
        bytes calldata reqId,
        SchnorrSign calldata sign
    ) public {
        bytes32 hash = keccak256(
            abi.encodePacked(
                muonAppId,
                reqId,
                msg.sender,
                raffleId,
                nonce,
                multiplier
            )
        );
        bool verified = muonVerify(reqId, uint256(hash), sign, muonPublicKey);
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

    function _verifyNonce(uint32 nonce) internal {
        require(!usedNonces[msg.sender][nonce], "Signature is already used");
        usedNonces[msg.sender][nonce] = true;
    }
}
