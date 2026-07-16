package com.ingilizce.calismaapp.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.ingilizce.calismaapp.entity.Comment;
import com.ingilizce.calismaapp.entity.Notification;
import com.ingilizce.calismaapp.entity.Post;
import com.ingilizce.calismaapp.entity.PostLike;
import com.ingilizce.calismaapp.entity.User;
import com.ingilizce.calismaapp.repository.CommentRepository;
import com.ingilizce.calismaapp.repository.PostLikeRepository;
import com.ingilizce.calismaapp.repository.PostRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class SocialServiceTest {

    private PostRepository postRepository;
    private CommentRepository commentRepository;
    private PostLikeRepository postLikeRepository;
    private NotificationService notificationService;
    private SocialService service;

    @BeforeEach
    void setUp() {
        postRepository = mock(PostRepository.class);
        commentRepository = mock(CommentRepository.class);
        postLikeRepository = mock(PostLikeRepository.class);
        notificationService = mock(NotificationService.class);
        service = new SocialService(postRepository, commentRepository, postLikeRepository, notificationService);
    }

    @Test
    void createPostShouldPersistContentAndMediaUrl() {
        User owner = user(1L, "owner@example.com");
        when(postRepository.save(any(Post.class))).thenAnswer(invocation -> invocation.getArgument(0));

        Post post = service.createPost(owner, "I learned five words today", "https://cdn.example/post.png");

        assertSame(owner, post.getUser());
        assertEquals("I learned five words today", post.getContent());
        assertEquals("https://cdn.example/post.png", post.getMediaUrl());
        verify(postRepository).save(post);
    }

    @Test
    void feedMethodsShouldDelegateToRepositories() {
        User owner = user(1L, "owner@example.com");
        Post first = post(10L, owner, 0);
        Post second = post(11L, owner, 0);
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(first, second));
        when(postRepository.findByUserOrderByCreatedAtDesc(owner)).thenReturn(List.of(second));

        assertEquals(List.of(first, second), service.getGlobalFeed());
        assertEquals(List.of(second), service.getUserPosts(owner));
    }

    @Test
    void getPostShouldReturnPostOrThrow() {
        User owner = user(1L, "owner@example.com");
        Post post = post(10L, owner, 0);
        when(postRepository.findById(10L)).thenReturn(Optional.of(post));
        when(postRepository.findById(99L)).thenReturn(Optional.empty());

        assertSame(post, service.getPost(10L));
        assertThrows(RuntimeException.class, () -> service.getPost(99L));
    }

    @Test
    void toggleLikeShouldCreateLikeAndNotifyOwnerAtMilestone() {
        User owner = user(1L, "owner@example.com");
        User liker = user(2L, "liker@example.com");
        Post post = post(10L, owner, 4);
        when(postRepository.findById(10L)).thenReturn(Optional.of(post));
        when(postLikeRepository.findByUserAndPost(liker, post)).thenReturn(Optional.empty());

        boolean liked = service.toggleLike(liker, 10L);

        assertTrue(liked);
        assertEquals(5, post.getLikeCount());
        verify(postLikeRepository).save(any(PostLike.class));
        verify(postRepository).save(post);
        verify(notificationService).createNotification(
                eq(owner),
                eq(Notification.NotificationType.LIKE),
                contains("5"),
                eq(10L));
    }

    @Test
    void toggleLikeShouldNotNotifyWhenOwnerLikesOwnPostOrCountIsNotMilestone() {
        User owner = user(1L, "owner@example.com");
        Post ownPost = post(10L, owner, 4);
        Post normalPost = post(11L, owner, 5);
        User other = user(2L, "other@example.com");
        when(postRepository.findById(10L)).thenReturn(Optional.of(ownPost));
        when(postRepository.findById(11L)).thenReturn(Optional.of(normalPost));
        when(postLikeRepository.findByUserAndPost(owner, ownPost)).thenReturn(Optional.empty());
        when(postLikeRepository.findByUserAndPost(other, normalPost)).thenReturn(Optional.empty());

        assertTrue(service.toggleLike(owner, 10L));
        assertTrue(service.toggleLike(other, 11L));

        verify(notificationService, never()).createNotification(any(), eq(Notification.NotificationType.LIKE), any(), any());
    }

    @Test
    void toggleLikeShouldRemoveExistingLikeAndNotDropBelowZero() {
        User owner = user(1L, "owner@example.com");
        User liker = user(2L, "liker@example.com");
        Post post = post(10L, owner, 0);
        PostLike existingLike = new PostLike(liker, post);
        when(postRepository.findById(10L)).thenReturn(Optional.of(post));
        when(postLikeRepository.findByUserAndPost(liker, post)).thenReturn(Optional.of(existingLike));

        boolean liked = service.toggleLike(liker, 10L);

        assertFalse(liked);
        assertEquals(0, post.getLikeCount());
        verify(postLikeRepository).delete(existingLike);
        verify(postRepository).save(post);
    }

    @Test
    void commentPostShouldIncrementCountAndNotifyOwnerForNonSelfComment() {
        User owner = user(1L, "owner@example.com");
        User commenter = user(2L, "commenter@example.com");
        Post post = post(10L, owner, 0);
        post.setCommentCount(2);
        when(postRepository.findById(10L)).thenReturn(Optional.of(post));
        when(commentRepository.save(any(Comment.class))).thenAnswer(invocation -> invocation.getArgument(0));

        Comment comment = service.commentPost(commenter, 10L, "Great progress");

        assertSame(commenter, comment.getUser());
        assertSame(post, comment.getPost());
        assertEquals("Great progress", comment.getContent());
        assertEquals(3, post.getCommentCount());
        verify(postRepository).save(post);
        verify(notificationService).createNotification(
                eq(owner),
                eq(Notification.NotificationType.COMMENT),
                contains("Great progress"),
                eq(10L));
    }

    @Test
    void commentPostShouldSkipNotificationForSelfCommentAndListComments() {
        User owner = user(1L, "owner@example.com");
        Post post = post(10L, owner, 0);
        Comment comment = new Comment(owner, post, "Self note");
        when(postRepository.findById(10L)).thenReturn(Optional.of(post));
        when(commentRepository.save(any(Comment.class))).thenReturn(comment);
        when(commentRepository.findByPostOrderByCreatedAtAsc(post)).thenReturn(List.of(comment));

        assertSame(comment, service.commentPost(owner, 10L, "Self note"));
        assertEquals(List.of(comment), service.getComments(10L));
        verify(notificationService, never()).createNotification(any(), eq(Notification.NotificationType.COMMENT), any(), any());
    }

    @Test
    void actionsShouldThrowWhenPostDoesNotExist() {
        User user = user(1L, "user@example.com");
        when(postRepository.findById(404L)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> service.toggleLike(user, 404L));
        assertThrows(RuntimeException.class, () -> service.commentPost(user, 404L, "x"));
        assertThrows(RuntimeException.class, () -> service.getComments(404L));
    }

    private static User user(Long id, String email) {
        User user = new User();
        user.setId(id);
        user.setEmail(email);
        user.setDisplayName(email);
        return user;
    }

    private static Post post(Long id, User owner, int likeCount) {
        Post post = new Post(owner, "content");
        post.setId(id);
        post.setLikeCount(likeCount);
        return post;
    }
}
