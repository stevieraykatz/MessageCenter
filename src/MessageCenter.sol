// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {BasefriendsHelper} from "./BasefriendsHelper.sol";

/**
 * @title MessageCenter
 * @dev A smart contract for managing messages with user authorizations and oracle delivery confirmations
 */
contract MessageCenter is BasefriendsHelper {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    enum MessageStatus {
        Sent,
        Delivered
    }

    struct Message {
        address sender;
        string subject;
        string body;
        uint256 id;
        uint256 timestamp;
        MessageStatus status;
        address recipient;
        bool externalAuth;
    }

    struct Authorization {
        address sender;
        address oracle;
        bool isAuthorized;
        uint256 messageCount;
    }

    struct SenderAuthorizationInfo {
        address user;
        address oracle;
        uint256 messageCount;
    }

    uint256 private globalNonce;
    mapping(uint256 messageId => Message message) private messages;
    mapping(address user => mapping(address sender => Authorization auth)) private authorizations;
    mapping(address sender => EnumerableSet.UintSet messageIds) private userMessages;
    mapping(address oracle => EnumerableSet.UintSet messageIds) private oracleMessages;
    mapping(address user => EnumerableSet.AddressSet senders) private userAuthorizedSenders;
    mapping(address sender => EnumerableSet.AddressSet users) private senderAuthorizedUsers;

    event AuthorizationGranted(address indexed user, address indexed sender, address indexed oracle);
    event AuthorizationRevoked(address indexed user, address indexed sender, address indexed oracle);
    event MessageSent(address indexed sender, address indexed recipient, uint256 indexed messageId);
    event MessageDelivered(uint256 indexed messageId);

    error AuthorizationAlreadyGranted();
    error AuthorizationNotFound();
    error InvalidMessageId();
    error MessageAlreadyDelivered();
    error NotAuthorizedToSend(address sender, address recipient);
    error NoZeroAddress();
    error OnlyAuthorizedOracle();
    error UnauthorizedOracle();

    modifier onlyAuthorizedOracle(uint256 _messageId) {
        Message storage message = messages[_messageId];
        Authorization storage auth = authorizations[message.recipient][message.sender];
        if (auth.oracle != msg.sender) revert UnauthorizedOracle();
        _;
    }

    modifier noZeroAddress(address sender, address oracle) {
        if (sender == address(0) || oracle == address(0)) revert NoZeroAddress();
        _;
    }

    constructor(address registry, address basefriends) BasefriendsHelper(registry, basefriends) {}

    /**
     * @dev Grants authorization to a sender and its associated oracle to send messages to the user
     * @param _sender Address of the sender
     * @param _oracle Address of the oracle
     */
    function grantAuthorization(address _sender, address _oracle) external noZeroAddress(_sender, _oracle) {
        if (authorizations[msg.sender][_sender].isAuthorized) revert AuthorizationAlreadyGranted();

        userAuthorizedSenders[msg.sender].add(_sender);
        authorizations[msg.sender][_sender] =
            Authorization({sender: _sender, oracle: _oracle, isAuthorized: true, messageCount: 0});

        emit AuthorizationGranted(msg.sender, _sender, _oracle);
    }

    /**
     * @dev Revokes authorization from a sender
     * @param _sender Address of the sender
     */
    function revokeAuthorization(address _sender) external {
        if (!authorizations[msg.sender][_sender].isAuthorized) revert AuthorizationNotFound();
        address oracle = authorizations[msg.sender][_sender].oracle;
        delete authorizations[msg.sender][_sender];
        userAuthorizedSenders[msg.sender].remove(_sender);
        senderAuthorizedUsers[_sender].remove(msg.sender);
        emit AuthorizationRevoked(msg.sender, _sender, oracle);
    }

    /**
     * @dev Generates a pseudo-random message ID
     * @param _sender Address of the message sender
     * @param _recipient Address of the message recipient
     * @return A pseudo-random uint256 ID
     */
    function generateMessageId(address _sender, address _recipient) private returns (uint256) {
        globalNonce++;

        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _sender, _recipient, globalNonce)));
    }

    /**
     * @dev Sends messages to multiple recipients
     * @param _recipients Array of recipient addresses
     * @param _body Message body
     * @param _subject Message subject
     */
    function sendMessage(address[] calldata _recipients, string calldata _body, string calldata _subject) external {
        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];

            bool externalAuth = _sendMessageAuth(recipient);

            uint256 messageId = generateMessageId(msg.sender, recipient);
            messages[messageId] = Message({
                id: messageId,
                sender: msg.sender,
                subject: _subject,
                body: _body,
                timestamp: block.timestamp,
                status: MessageStatus.Sent,
                recipient: recipient,
                externalAuth: externalAuth
            });

            userMessages[recipient].add(messageId);
            oracleMessages[authorizations[recipient][msg.sender].oracle].add(messageId);
            authorizations[recipient][msg.sender].messageCount++;

            emit MessageSent(msg.sender, recipient, messageId);
        }
    }

    function _sendMessageAuth(address recipient) internal view returns (bool externalAuth) {
            if (authorizations[recipient][msg.sender].isAuthorized) {
                return false;
            } else if(_getBasefriendsAuth(recipient)) {
                return true;
            } else {
                revert NotAuthorizedToSend(msg.sender, recipient);
            }
    }

    function _getBasefriendsAuth(address recipient) internal view returns (bool) {
        return checkAddrIsFollowed(recipient, msg.sender);
    }

    /**
     * @dev Marks a message as delivered
     * @param _messageId ID of the message
     */
    function markMessageAsDelivered(uint256 _messageId) external {
        if (messages[_messageId].id == 0) revert InvalidMessageId();
        if (messages[_messageId].status != MessageStatus.Sent) revert MessageAlreadyDelivered();

        address recipient = messages[_messageId].recipient;
        address sender = messages[_messageId].sender;
        if (authorizations[recipient][sender].oracle != msg.sender) revert UnauthorizedOracle();

        messages[_messageId].status = MessageStatus.Delivered;
        emit MessageDelivered(_messageId);
    }

    /**
     * @dev Retrieves the authorization details for a user and sender
     * @param _user Address of the user
     * @param _sender Address of the sender
     * @return Authorization struct
     */
    function getAuthorization(address _user, address _sender) external view returns (Authorization memory) {
        return authorizations[_user][_sender];
    }

    /**
     * @dev Retrieves all Messages received by the calling user
     * @return Array of Message structs
     */
    function getUserMessages() external view returns (Message[] memory) {
        EnumerableSet.UintSet storage messageSet = userMessages[msg.sender];
        uint256 totalMessages = messageSet.length();
        Message[] memory result = new Message[](totalMessages);

        for (uint256 i = 0; i < totalMessages; i++) {
            uint256 messageId = messageSet.at(i);
            result[i] = messages[messageId];
        }

        return result;
    }

    /**
     * @dev Retrieves all authorizations for the calling user
     * @return authsInfo An array of Authorization structs containing all authorizations for the calling user
     */
    function getUserAuthorizations() external view returns (Authorization[] memory authsInfo) {
        address[] memory senders = userAuthorizedSenders[msg.sender].values();
        authsInfo = new Authorization[](senders.length);

        for (uint256 i = 0; i < senders.length; i++) {
            Authorization memory auth = authorizations[msg.sender][senders[i]];
            authsInfo[i] = Authorization({
                sender: auth.sender,
                oracle: auth.oracle,
                isAuthorized: auth.isAuthorized,
                messageCount: auth.messageCount
            });
        }

        return authsInfo;
    }

    /**
     * @dev Retrieves all Messages that the calling oracle can access
     * @return Array of Message structs
     */
    function getOracleMessages() external view returns (Message[] memory) {
        EnumerableSet.UintSet storage messageSet = oracleMessages[msg.sender];
        uint256 totalMessages = messageSet.length();
        Message[] memory result = new Message[](totalMessages);

        for (uint256 i = 0; i < totalMessages; i++) {
            uint256 messageId = messageSet.at(i);
            result[i] = messages[messageId];
        }

        return result;
    }

    /**
     * @dev Retrieves all authorizations where the calling address is the oracle
     * @return Array of Authorization structs
     */
    function getOracleAuthorizations() external view returns (Authorization[] memory) {
        Authorization[] memory authInfos = new Authorization[](senderAuthorizedUsers[msg.sender].length());
        uint256 index = 0;

        address[] memory authorizedUsers = senderAuthorizedUsers[msg.sender].values();
        for (uint256 i = 0; i < authorizedUsers.length; i++) {
            address user = authorizedUsers[i];
            Authorization memory auth = authorizations[user][msg.sender];

            if (auth.oracle == msg.sender) {
                authInfos[index] = Authorization({
                    sender: auth.sender,
                    oracle: auth.oracle,
                    isAuthorized: auth.isAuthorized,
                    messageCount: auth.messageCount
                });
                index++;
            }
        }

        // Resize the array to remove any empty elements
        assembly {
            mstore(authInfos, index)
        }

        return authInfos;
    }

    /**
     * @dev Retrieves all authorizations for the calling sender
     * @return Array of SenderAuthorizationInfo structs
     */
    function getSenderAuthorizations() external view returns (SenderAuthorizationInfo[] memory) {
        address[] memory authorizedUsers = senderAuthorizedUsers[msg.sender].values();
        SenderAuthorizationInfo[] memory authInfos = new SenderAuthorizationInfo[](authorizedUsers.length);

        for (uint256 i = 0; i < authorizedUsers.length; i++) {
            Authorization storage auth = authorizations[authorizedUsers[i]][msg.sender];
            authInfos[i] = SenderAuthorizationInfo({
                user: authorizedUsers[i],
                oracle: auth.oracle,
                messageCount: auth.messageCount
            });
        }

        return authInfos;
    }
}
