// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/MessageCenter.sol";

contract MessageCenterTest is Test {
    MessageCenter public messageCenter;
    address public user1;
    address public user2;
    address public sender1;
    address public sender2;
    address public oracle1;
    address public oracle2;

    event Debug(string message, address user, address sender);

    function setUp() public {
        messageCenter = new MessageCenter();
        user1 = address(0x1);
        user2 = address(0x2);
        sender1 = address(0x3);
        sender2 = address(0x4);
        oracle1 = address(0x5);
        oracle2 = address(0x6);
    }

    function testGrantAuthorization() public {
        vm.prank(user1);
        messageCenter.grantAuthorization(sender1, oracle1);

        MessageCenter.Authorization memory auth = messageCenter
            .getAuthorization(user1, sender1);
        assertEq(auth.sender, sender1);
        assertEq(auth.oracle, oracle1);
        assertTrue(auth.isAuthorized);
        assertEq(auth.messageCount, 0);
    }

    function testRevokeAuthorization() public {
        vm.startPrank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );
        messageCenter.revokeAuthorization(sender1);
        vm.stopPrank();

        MessageCenter.Authorization memory auth = messageCenter
            .getAuthorization(user1, sender1);
        assertFalse(auth.isAuthorized);
    }

    function testPreventUnauthorizedRevocation() public {
        vm.prank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );

        vm.prank(user2);
        vm.expectRevert(MessageCenter.AuthorizationNotFound.selector);
        messageCenter.revokeAuthorization(sender1);
    }

    function testSendMessage() public {
        vm.prank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.startPrank(sender1);
        messageCenter.sendMessage(recipients, "Test message", "Subject");

        vm.startPrank(user1);
        MessageCenter.Message[] memory messages = messageCenter
            .getUserMessages();
        assertEq(messages.length, 1);
        assertEq(messages[0].sender, sender1);
        assertEq(messages[0].body, "Test message");
        assertEq(messages[0].recipient, user1);
    }

    function testPreventUnauthorizedMessages() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(sender2);
        vm.expectRevert(abi.encodeWithSelector(MessageCenter.NotAuthorizedToSend.selector, sender2, user1));
        messageCenter.sendMessage(
            recipients,
            "Unauthorized message",
            "Subject"
        );
    }

    function testMarkMessageAsDelivered() public {
        vm.prank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.startPrank(sender1);
        messageCenter.sendMessage(recipients, "Test message", "Subject");

        // Retrieve the message ID
        vm.startPrank(user1);
        MessageCenter.Message[] memory userMessages = messageCenter
            .getUserMessages();
        require(userMessages.length > 0, "No messages found");
        uint256 messageId = userMessages[0].id;

        vm.startPrank(oracle1);
        messageCenter.markMessageAsDelivered(messageId);

        vm.startPrank(user1);
        MessageCenter.Message[] memory updatedMessages = messageCenter
            .getUserMessages();
        assertEq(
            uint(updatedMessages[0].status),
            uint(MessageCenter.MessageStatus.Delivered)
        );
    }

    function testPreventUnauthorizedOracleMarkingDelivered() public {
        vm.prank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(sender1);
        messageCenter.sendMessage(recipients, "Test message", "Subject");

        // Retrieve the message ID
        vm.prank(user1);
        MessageCenter.Message[] memory userMessages = messageCenter
            .getUserMessages();
        require(userMessages.length > 0, "No messages found");
        uint256 messageId = userMessages[0].id;

        vm.prank(oracle2);
        vm.expectRevert(MessageCenter.UnauthorizedOracle.selector);
        messageCenter.markMessageAsDelivered(messageId);
    }

    function testGetUserAuthorizations() public {
        vm.startPrank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );
        messageCenter.grantAuthorization(
            sender2,
            oracle2
        );

        MessageCenter.Authorization[] memory auths = messageCenter
            .getUserAuthorizations();

        assertEq(auths.length, 2, "Should have 2 authorizations");

        assertEq(auths[0].sender, sender1);
        assertEq(auths[0].oracle, oracle1);
        assertTrue(auths[0].isAuthorized);

        assertEq(auths[1].sender, sender2);
        assertEq(auths[1].oracle, oracle2);
        assertTrue(auths[1].isAuthorized);

        vm.stopPrank();
    }

    function testGetUserAuthorizationsAfterRevoke() public {
        vm.startPrank(user1);
        messageCenter.grantAuthorization(
            sender1,
            oracle1
        );
        messageCenter.grantAuthorization(
            sender2,
            oracle2
        );
        messageCenter.revokeAuthorization(sender1);

        MessageCenter.Authorization[] memory auths = messageCenter
            .getUserAuthorizations();

        assertEq(auths.length, 1, "Should have 1 authorization after revoke");

        assertEq(auths[0].sender, sender2);
        assertEq(auths[0].oracle, oracle2);
        assertTrue(auths[0].isAuthorized);

        vm.stopPrank();
    }
}