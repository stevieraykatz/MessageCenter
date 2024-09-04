// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title MessageCenter
 * @dev A smart contract for managing messages with user authorizations and oracle delivery confirmations
 */
contract MessageCenter is ReentrancyGuard {
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
    }

    struct Authorization {
        address sender;
        address oracle;
        bool isAuthorized;
        uint256 messageCount;
        bytes32 encryptedEmail;
        bytes32 encryptedPhone;
    }

    struct AuthorizationInfo {
        address sender;
        address oracle;
        bool isAuthorized;
        uint256 messageCount;
        bytes32 encryptedEmail;
        bytes32 encryptedPhone;
    }

    struct SenderAuthorizationInfo {
        address user;
        address oracle;
        uint256 messageCount;
    }

    mapping(uint256 => Message) private messages;
    mapping(address => mapping(address => Authorization))
        private authorizations;
    mapping(address => uint256) private userNonce;
    mapping(address => EnumerableSet.UintSet) private userMessages;
    mapping(address => EnumerableSet.UintSet) private oracleMessages;
    mapping(address => EnumerableSet.AddressSet) private userAuthorizedSenders;
    mapping(address => EnumerableSet.AddressSet) private senderAuthorizedUsers;

    uint256 private globalNonce;
    uint256 private constant PRIME1 = 2971215073;
    uint256 private constant PRIME2 = 433494437;

    event AuthorizationGranted(
        address indexed user,
        address indexed sender,
        address indexed oracle
    );
    event AuthorizationRevoked(
        address indexed user,
        address indexed sender,
        address indexed oracle
    );
    event MessageSent(
        address indexed sender,
        address indexed recipient,
        uint256 indexed messageId
    );
    event MessageDelivered(uint256 indexed messageId);

    modifier onlyAuthorizedOracle(uint256 _messageId) {
        Message storage message = messages[_messageId];
        Authorization storage auth = authorizations[message.recipient][
            message.sender
        ];
        require(auth.oracle == msg.sender, "Not an authorized oracle");
        _;
    }

    /**
     * @dev Grants authorization to a sender and its associated oracle to send messages to the user
     * @param _sender Address of the sender
     * @param _oracle Address of the oracle
     * @param _email Email of the user
     * @param _phone Phone number of the user
     */
    function grantAuthorization(
        address _sender,
        address _oracle,
        string calldata _email,
        string calldata _phone
    ) external {
        require(
            _sender != address(0) && _oracle != address(0),
            "Invalid addresses"
        );
        require(
            !authorizations[msg.sender][_sender].isAuthorized,
            "Authorization already granted"
        );

        uint256 currentNonce = userNonce[msg.sender]++;
        bytes32 encryptedEmail = keccak256(
            abi.encodePacked(
                _email,
                msg.sender,
                currentNonce,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );
        bytes32 encryptedPhone = keccak256(
            abi.encodePacked(
                _phone,
                msg.sender,
                currentNonce,
                block.timestamp,
                blockhash(block.number - 1)
            )
        );

        authorizations[msg.sender][_sender] = Authorization({
            sender: _sender,
            oracle: _oracle,
            isAuthorized: true,
            messageCount: 0,
            encryptedEmail: encryptedEmail,
            encryptedPhone: encryptedPhone
        });

        require(
            userAuthorizedSenders[msg.sender].add(_sender),
            "Failed to add sender to user's authorized list"
        );
        require(
            senderAuthorizedUsers[_sender].add(msg.sender),
            "Failed to add user to sender's authorized list"
        );

        emit AuthorizationGranted(msg.sender, _sender, _oracle);
    }

    /**
     * @dev Revokes authorization from a sender
     * @param _sender Address of the sender
     */
    function revokeAuthorization(address _sender) external {
        require(
            authorizations[msg.sender][_sender].isAuthorized,
            "Authorization not found"
        );
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
    function generateMessageId(
        address _sender,
        address _recipient
    ) private returns (uint256) {
        globalNonce++;

        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        _sender,
                        _recipient,
                        globalNonce,
                        PRIME1,
                        PRIME2
                    )
                )
            );
    }

    /**
     * @dev Sends messages to multiple recipients
     * @param _recipients Array of recipient addresses
     * @param _body Message body
     * @param _subject Message subject
     */
    function sendMessage(
        address[] calldata _recipients,
        string calldata _body,
        string calldata _subject
    ) external nonReentrant {
        for (uint i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            require(
                authorizations[recipient][msg.sender].isAuthorized,
                "Not authorized to send messages to this user"
            );

            uint256 messageId = generateMessageId(msg.sender, recipient);
            messages[messageId] = Message({
                id: messageId,
                sender: msg.sender,
                subject: _subject,
                body: _body,
                timestamp: block.timestamp,
                status: MessageStatus.Sent,
                recipient: recipient
            });

            userMessages[recipient].add(messageId);
            oracleMessages[authorizations[recipient][msg.sender].oracle].add(
                messageId
            );
            authorizations[recipient][msg.sender].messageCount++;

            emit MessageSent(msg.sender, recipient, messageId);
        }
    }

    /**
     * @dev Marks a message as delivered
     * @param _messageId ID of the message
     */
    function markMessageAsDelivered(uint256 _messageId) external {
        require(messages[_messageId].id != 0, "Message does not exist");
        require(
            messages[_messageId].status == MessageStatus.Sent,
            "Message already delivered"
        );

        address recipient = messages[_messageId].recipient;
        address sender = messages[_messageId].sender;
        require(
            authorizations[recipient][sender].oracle == msg.sender,
            "Not an authorized oracle"
        );

        messages[_messageId].status = MessageStatus.Delivered;
        emit MessageDelivered(_messageId);
    }

    /**
     * @dev Retrieves the authorization details for a user and sender
     * @param _user Address of the user
     * @param _sender Address of the sender
     * @return Authorization struct
     */
    function getAuthorization(
        address _user,
        address _sender
    ) external view returns (Authorization memory) {
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
     * @return authsInfo An array of AuthorizationInfo structs containing all authorizations for the calling user
     */
    function getUserAuthorizations()
        external
        view
        returns (AuthorizationInfo[] memory authsInfo)
    {
        address[] memory senders = userAuthorizedSenders[msg.sender].values();
        authsInfo = new AuthorizationInfo[](senders.length);

        for (uint i = 0; i < senders.length; i++) {
            Authorization memory auth = authorizations[msg.sender][senders[i]];
            authsInfo[i] = AuthorizationInfo({
                sender: auth.sender,
                oracle: auth.oracle,
                isAuthorized: auth.isAuthorized,
                messageCount: auth.messageCount,
                encryptedEmail: auth.encryptedEmail,
                encryptedPhone: auth.encryptedPhone
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
     * @return Array of AuthorizationInfo structs
     */
    function getOracleAuthorizations()
        external
        view
        returns (AuthorizationInfo[] memory)
    {
        AuthorizationInfo[] memory authInfos = new AuthorizationInfo[](
            senderAuthorizedUsers[msg.sender].length()
        );
        uint256 index = 0;

        address[] memory authorizedUsers = senderAuthorizedUsers[msg.sender]
            .values();
        for (uint256 i = 0; i < authorizedUsers.length; i++) {
            address user = authorizedUsers[i];
            Authorization memory auth = authorizations[user][msg.sender];

            if (auth.oracle == msg.sender) {
                authInfos[index] = AuthorizationInfo({
                    sender: auth.sender,
                    oracle: auth.oracle,
                    isAuthorized: auth.isAuthorized,
                    messageCount: auth.messageCount,
                    encryptedEmail: auth.encryptedEmail,
                    encryptedPhone: auth.encryptedPhone
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
    function getSenderAuthorizations()
        external
        view
        returns (SenderAuthorizationInfo[] memory)
    {
        address[] memory authorizedUsers = senderAuthorizedUsers[msg.sender]
            .values();
        SenderAuthorizationInfo[]
            memory authInfos = new SenderAuthorizationInfo[](
                authorizedUsers.length
            );

        for (uint i = 0; i < authorizedUsers.length; i++) {
            Authorization storage auth = authorizations[authorizedUsers[i]][
                msg.sender
            ];
            authInfos[i] = SenderAuthorizationInfo({
                user: authorizedUsers[i],
                oracle: auth.oracle,
                messageCount: auth.messageCount
            });
        }

        return authInfos;
    }
}