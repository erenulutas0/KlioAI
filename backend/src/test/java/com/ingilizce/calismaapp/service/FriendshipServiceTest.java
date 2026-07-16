package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.Friendship;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.FriendshipRepository;
import com.ingilizce.calismaapp.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Optional;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class FriendshipServiceTest {

    @InjectMocks
    private FriendshipService friendshipService;

    @Mock
    private FriendshipRepository friendshipRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private NotificationService notificationService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void sendRequest_ShouldCreatePendingFriendship() {
        // Arrange
        Long requesterId = 1L;
        String addresseeEmail = "friend@example.com";

        User requester = new User();
        requester.setId(requesterId);
        requester.setEmail("me@example.com");

        User addressee = new User();
        addressee.setId(2L);
        addressee.setEmail(addresseeEmail);

        when(userRepository.findById(requesterId)).thenReturn(Optional.of(requester));
        when(userRepository.findByEmail(addresseeEmail)).thenReturn(Optional.of(addressee));
        when(friendshipRepository.findExistingFriendship(requester, addressee)).thenReturn(Optional.empty());

        // Act
        friendshipService.sendRequest(requesterId, addresseeEmail);

        // Assert
        verify(friendshipRepository, times(1)).save(any(Friendship.class));
    }

    @Test
    void sendRequest_ShouldFail_IfSelfRequest() {
        // Arrange
        Long requesterId = 1L;
        String addresseeEmail = "me@example.com";

        User requester = new User();
        requester.setId(requesterId);
        requester.setEmail("me@example.com");

        User addressee = new User(); // Same user mock
        addressee.setId(requesterId);
        addressee.setEmail("me@example.com");

        when(userRepository.findById(requesterId)).thenReturn(Optional.of(requester));
        when(userRepository.findByEmail(addresseeEmail)).thenReturn(Optional.of(addressee));

        // Act & Assert
        Exception exception = assertThrows(RuntimeException.class, () -> {
            friendshipService.sendRequest(requesterId, addresseeEmail);
        });

        assertEquals("Kendinize istek gönderemezsiniz.", exception.getMessage());
        verify(friendshipRepository, never()).save(any());
    }

    @Test
    void acceptRequest_ShouldUpdateStatus() {
        // Arrange
        Long requestId = 10L;
        Friendship pendingFriendship = new Friendship();
        pendingFriendship.setId(requestId);
        pendingFriendship.setStatus(Friendship.Status.PENDING);

        User addressee = new User();
        addressee.setId(50L); // Matches the ID passed in acceptRequest
        pendingFriendship.setAddressee(addressee);

        when(friendshipRepository.findById(requestId)).thenReturn(Optional.of(pendingFriendship));

        // Act
        friendshipService.acceptRequest(requestId, 50L);

        // Assert
        assertEquals(Friendship.Status.ACCEPTED, pendingFriendship.getStatus());
        verify(friendshipRepository, times(1)).save(pendingFriendship);
    }

    @Test
    void sendRequest_ShouldFail_IfFriendshipAlreadyExists() {
        Long requesterId = 1L;
        String addresseeEmail = "friend@example.com";
        User requester = user(requesterId, "me@example.com");
        User addressee = user(2L, addresseeEmail);

        when(userRepository.findById(requesterId)).thenReturn(Optional.of(requester));
        when(userRepository.findByEmail(addresseeEmail)).thenReturn(Optional.of(addressee));
        when(friendshipRepository.findExistingFriendship(requester, addressee))
                .thenReturn(Optional.of(new Friendship(requester, addressee)));

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> friendshipService.sendRequest(requesterId, addresseeEmail));

        assertEquals("Zaten bir istek var veya arkadaşsınız.", exception.getMessage());
        verify(friendshipRepository, never()).save(any());
        verify(notificationService, never()).createNotification(any(), any(), any(), any());
    }

    @Test
    void acceptRequest_ShouldFail_IfUserIsNotAddressee() {
        Friendship pendingFriendship = new Friendship();
        pendingFriendship.setId(10L);
        pendingFriendship.setAddressee(user(50L, "friend@example.com"));
        when(friendshipRepository.findById(10L)).thenReturn(Optional.of(pendingFriendship));

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> friendshipService.acceptRequest(10L, 99L));

        assertEquals("Bu isteği onaylama yetkiniz yok.", exception.getMessage());
        verify(friendshipRepository, never()).save(any());
    }

    @Test
    void removeFriend_ShouldDeleteExistingFriendship() {
        User user = user(1L, "me@example.com");
        User friend = user(2L, "friend@example.com");
        Friendship friendship = new Friendship(user, friend);

        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(userRepository.findById(2L)).thenReturn(Optional.of(friend));
        when(friendshipRepository.findExistingFriendship(user, friend)).thenReturn(Optional.of(friendship));

        friendshipService.removeFriend(1L, 2L);

        verify(friendshipRepository).delete(friendship);
    }

    @Test
    void removeFriend_ShouldFail_WhenFriendshipDoesNotExist() {
        User user = user(1L, "me@example.com");
        User friend = user(2L, "friend@example.com");

        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(userRepository.findById(2L)).thenReturn(Optional.of(friend));
        when(friendshipRepository.findExistingFriendship(user, friend)).thenReturn(Optional.empty());

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> friendshipService.removeFriend(1L, 2L));

        assertEquals("Arkadaşlık bulunamadı.", exception.getMessage());
    }

    @Test
    void friendStatusMethods_ShouldReturnAcceptedPendingOrNone() {
        User user = user(1L, "me@example.com");
        User friend = user(2L, "friend@example.com");
        Friendship accepted = new Friendship(user, friend);
        accepted.setStatus(Friendship.Status.ACCEPTED);
        Friendship pending = new Friendship(user, friend);

        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(userRepository.findById(2L)).thenReturn(Optional.of(friend));
        when(friendshipRepository.findExistingFriendship(user, friend))
                .thenReturn(Optional.of(accepted), Optional.of(pending), Optional.empty());

        assertTrue(friendshipService.isFriend(1L, 2L));
        assertEquals("PENDING", friendshipService.getFriendshipStatus(1L, 2L));
        assertEquals("NONE", friendshipService.getFriendshipStatus(1L, 2L));
    }

    @Test
    void listMethods_ShouldMapAcceptedFriendsAndPendingRequests() {
        User user = user(1L, "me@example.com");
        User friendFromRequesterSide = user(2L, "a@example.com");
        User friendFromAddresseeSide = user(3L, "b@example.com");
        Friendship first = accepted(user, friendFromRequesterSide);
        Friendship second = accepted(friendFromAddresseeSide, user);
        Friendship pending = new Friendship(friendFromRequesterSide, user);

        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(friendshipRepository.findAllAcceptedFriends(user)).thenReturn(List.of(first, second));
        when(friendshipRepository.findByAddresseeAndStatus(user, Friendship.Status.PENDING))
                .thenReturn(List.of(pending));

        List<User> friends = friendshipService.getFriends(1L);
        List<Friendship> pendingRequests = friendshipService.getPendingRequests(1L);

        assertEquals(List.of(friendFromRequesterSide, friendFromAddresseeSide), friends);
        assertEquals(List.of(pending), pendingRequests);
    }

    private static User user(Long id, String email) {
        User user = new User();
        user.setId(id);
        user.setEmail(email);
        user.setDisplayName(email);
        return user;
    }

    private static Friendship accepted(User requester, User addressee) {
        Friendship friendship = new Friendship(requester, addressee);
        friendship.setStatus(Friendship.Status.ACCEPTED);
        return friendship;
    }
}
