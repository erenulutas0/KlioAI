package com.ingilizce.calismaapp.controller;

import com.ingilizce.calismaapp.entity.Friendship;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.UserRepository;
import com.ingilizce.calismaapp.service.FriendshipService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class FriendshipControllerTest {

    private FriendshipService friendshipService;
    private UserRepository userRepository;
    private FriendshipController controller;

    @BeforeEach
    void setUp() {
        friendshipService = mock(FriendshipService.class);
        userRepository = mock(UserRepository.class);
        controller = new FriendshipController();
        ReflectionTestUtils.setField(controller, "friendshipService", friendshipService);
        ReflectionTestUtils.setField(controller, "userRepository", userRepository);
    }

    @Test
    void sendRequestReturnsServiceMessage() {
        when(friendshipService.sendRequest(1L, "friend@example.com"))
                .thenReturn("Request sent");

        var response = controller.sendRequest(Map.of("email", "friend@example.com"), 1L);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("Request sent", response.getBody().get("message"));
    }

    @Test
    void sendRequestReturnsBadRequestForServiceError() {
        when(friendshipService.sendRequest(1L, "missing@example.com"))
                .thenThrow(new IllegalArgumentException("User not found"));

        var response = controller.sendRequest(Map.of("email", "missing@example.com"), 1L);

        assertEquals(HttpStatus.BAD_REQUEST, response.getStatusCode());
        assertEquals("User not found", response.getBody().get("error"));
    }

    @Test
    void acceptAndRemoveFriendDelegateToService() {
        var acceptResponse = controller.acceptRequest(10L, 2L);
        var removeResponse = controller.removeFriend(3L, 2L);

        assertEquals(HttpStatus.OK, acceptResponse.getStatusCode());
        assertEquals("Arkadaşlık kabul edildi!", acceptResponse.getBody().get("message"));
        assertEquals(HttpStatus.OK, removeResponse.getStatusCode());
        assertEquals("Arkadaşlıktan çıkarıldı.", removeResponse.getBody().get("message"));
        verify(friendshipService).acceptRequest(10L, 2L);
        verify(friendshipService).removeFriend(2L, 3L);
    }

    @Test
    void acceptAndRemoveFriendReturnBadRequestForServiceErrors() {
        doThrow(new IllegalStateException("Not your request"))
                .when(friendshipService).acceptRequest(11L, 2L);
        doThrow(new IllegalStateException("Not friends"))
                .when(friendshipService).removeFriend(2L, 4L);

        var acceptResponse = controller.acceptRequest(11L, 2L);
        var removeResponse = controller.removeFriend(4L, 2L);

        assertEquals(HttpStatus.BAD_REQUEST, acceptResponse.getStatusCode());
        assertEquals("Not your request", acceptResponse.getBody().get("error"));
        assertEquals(HttpStatus.BAD_REQUEST, removeResponse.getStatusCode());
        assertEquals("Not friends", removeResponse.getBody().get("error"));
    }

    @Test
    void getFriendshipStatusReturnsAcceptedFlag() {
        when(friendshipService.getFriendshipStatus(1L, 2L)).thenReturn("ACCEPTED");

        var response = controller.getFriendshipStatus(2L, 1L);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals("ACCEPTED", response.getBody().get("status"));
        assertEquals(true, response.getBody().get("isFriend"));
    }

    @Test
    void getFriendsMapsSafeProfileFields() {
        User friend = user(2L, "friend@example.com", "Friend", "FRIEND#123", true);
        when(friendshipService.getFriends(1L)).thenReturn(List.of(friend));

        var response = controller.getFriends(1L);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        Map<String, Object> first = response.getBody().get(0);
        assertEquals(2L, first.get("id"));
        assertEquals("friend@example.com", first.get("email"));
        assertEquals("Friend", first.get("displayName"));
        assertEquals("FRIEND#123", first.get("userTag"));
        assertEquals(true, first.get("online"));
    }

    @Test
    void getPendingRequestsMapsRequesterFields() {
        Friendship friendship = new Friendship();
        friendship.setId(99L);
        friendship.setRequester(user(3L, "requester@example.com", "Requester", "REQ#777", false));
        friendship.setCreatedAt(LocalDateTime.of(2026, 7, 6, 10, 30));
        when(friendshipService.getPendingRequests(1L)).thenReturn(List.of(friendship));

        var response = controller.getPendingRequests(1L);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        Map<String, Object> first = response.getBody().get(0);
        assertEquals(99L, first.get("requestId"));
        assertEquals(3L, first.get("requesterId"));
        assertEquals("Requester", first.get("requesterName"));
        assertEquals("requester@example.com", first.get("requesterEmail"));
        assertEquals("REQ#777", first.get("requesterTag"));
        assertTrue(first.get("sentAt").toString().contains("2026-07-06T10:30"));
    }

    @Test
    void getUserProfileMapsFriendshipAndCurrentUserFlags() {
        User profile = user(5L, "profile@example.com", "Profile", "PRO#555", true);
        profile.setCreatedAt(LocalDateTime.of(2026, 1, 2, 3, 4));
        when(userRepository.findById(5L)).thenReturn(Optional.of(profile));
        when(friendshipService.getFriendshipStatus(5L, 5L)).thenReturn("NONE");

        var response = controller.getUserProfile(5L, 5L);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertEquals(5L, response.getBody().get("id"));
        assertEquals("Profile", response.getBody().get("displayName"));
        assertEquals("NONE", response.getBody().get("friendshipStatus"));
        assertEquals(false, response.getBody().get("isFriend"));
        assertEquals(true, response.getBody().get("isCurrentUser"));
        assertEquals(1, response.getBody().get("level"));
    }

    @Test
    void getUserProfileReturnsNotFoundForMissingUser() {
        when(userRepository.findById(404L)).thenReturn(Optional.empty());

        var response = controller.getUserProfile(404L, 1L);

        assertEquals(HttpStatus.NOT_FOUND, response.getStatusCode());
    }

    private static User user(Long id, String email, String displayName, String tag, boolean online) {
        User user = new User();
        user.setId(id);
        user.setEmail(email);
        user.setDisplayName(displayName);
        user.setUserTag(tag);
        user.setLastSeenAt(online ? LocalDateTime.now() : LocalDateTime.now().minusMinutes(10));
        user.setCreatedAt(LocalDateTime.of(2026, 1, 1, 12, 0));
        return user;
    }
}
