// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

abstract contract AbstractPrizetapRaffle is
    AccessControl,
    Pausable,
    VRFConsumerBaseV2
{
    using ECDSA for bytes32;

    enum Status {
        PENDING,
        OPEN,
        CLOSED,
        HELD,
        CLAIMED,
        REJECTED,
        REFUNDED
    }

    event VRFRequestSent(uint256 requestId);
    event VRFRequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Participate(address user, uint256 raffleId);

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(uint256 => uint256) public vrfRequests; // Map vrfRequestId to raffleId
    mapping(address => mapping(uint32 => bool)) public usedNonces;

    uint256 public lastRaffleId = 0;

    uint256 public validationPeriod = 7 days;

    VRFCoordinatorV2Interface private immutable CHAINLINK_VRF_COORDINATOR;

    uint64 chainlinkVrfSubscriptionId;

    bytes32 chainlinkKeyHash;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 100000;

    uint16 vrfRequestConfirmations = 3;

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
        address admin,
        address operator
    ) VRFConsumerBaseV2(_ChainlinkVRFCoordinator) {
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

    function confirmRaffle(uint256 raffleId) external virtual;

    function rejectRaffle(uint256 raffleId) external virtual;

    function participateInRaffle(
        uint256 raffleId,
        uint32 nonce,
        bytes memory signature,
        uint256 multiplier
    ) external virtual;

    function heldRaffle(uint256 raffleId) external virtual;

    function drawRaffle(
        uint256 raffleId,
        uint256[] memory randomWords
    ) internal virtual;

    function claimPrize(
        uint256 raffleId,
        bytes memory signature
    ) external virtual;

    function refundPrize(uint256 raffleId) external virtual;

    function getParticipants(
        uint256 raffleId
    ) public view virtual returns (address[] memory);

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

    function _verifySignature(
        bytes memory data,
        bytes memory signature
    ) internal view {
        address signer = keccak256(data).toEthSignedMessageHash().recover(
            signature
        );
        require(
            hasRole(OPERATOR_ROLE, signer) ||
                hasRole(DEFAULT_ADMIN_ROLE, signer),
            "Invalid signature"
        );
    }

    function emergencyWithdraw(
        uint256 amount,
        address to
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= address(this).balance, "INSUFFICIENT_BALANCE");
        payable(to).transfer(amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {}
}
