// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract PrizetapVRFClient is AccessControl, VRFConsumerBaseV2 {
    struct Request {
        uint256 expirationTime;
        uint256 numWords;
        uint256[] randomWords;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(uint256 => Request) public vrfRequests; // Map vrfRequestId to Request

    uint64 public chainlinkVrfSubscriptionId;

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 public chainlinkKeyHash;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 public callbackGasLimit = 100000;

    uint16 public vrfRequestConfirmations = 3;

    uint256 public validityPeriod = 600;

    uint256 public lastRequestId;

    VRFCoordinatorV2Interface private immutable CHAINLINK_VRF_COORDINATOR;

    event VRFRequestSent(uint256 requestId);
    event VRFRequestFulfilled(uint256 requestId, uint256[] randomWords);

    constructor(
        address _chainlinkVRFCoordinator,
        uint64 _chainlinkVRFSubscriptionId,
        bytes32 _chainlinkKeyHash,
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
    }

    function setVrfSubscriptionId(
        uint64 id
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainlinkVrfSubscriptionId = id;
    }

    function setVrfKeyHash(
        bytes32 keyHash
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainlinkKeyHash = keyHash;
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

    function setValidityPeriod(
        uint256 period
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validityPeriod = period;
    }

    function requestRandomWords(
        uint32 numWords
    ) external onlyRole(OPERATOR_ROLE) returns (uint256) {
        require(
            block.timestamp > vrfRequests[lastRequestId].expirationTime,
            "There is an in progress request"
        );
        // Will revert if subscription is not set and funded.
        lastRequestId = CHAINLINK_VRF_COORDINATOR.requestRandomWords(
            chainlinkKeyHash,
            chainlinkVrfSubscriptionId,
            vrfRequestConfirmations,
            callbackGasLimit,
            numWords
        );

        Request storage newRequest = vrfRequests[lastRequestId];
        newRequest.expirationTime = block.timestamp + validityPeriod;
        newRequest.numWords = numWords;

        emit VRFRequestSent(lastRequestId);

        return lastRequestId;
    }

    function getRandomWords(
        uint256 requestId
    ) external view returns (uint256[] memory) {
        return vrfRequests[requestId].randomWords;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        vrfRequests[_requestId].randomWords = _randomWords;

        emit VRFRequestFulfilled(_requestId, _randomWords);
    }
}
