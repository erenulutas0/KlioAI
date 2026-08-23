package com.ingilizce.calismaapp.service;

import com.ingilizce.calismaapp.entity.LanguageProfile;
import com.ingilizce.calismaapp.repository.LanguageProfileRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.List;
import java.util.NoSuchElementException;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class LanguageProfileServiceTest {

    private static final Long USER_ID = 42L;

    @Mock
    private LanguageProfileRepository repository;

    private LanguageProfileService service;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new LanguageProfileService(repository);
        when(repository.save(any(LanguageProfile.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    @Test
    void ensureDefaultProfile_ReturnsTheActiveProfile_WhenOneExists() {
        LanguageProfile active = LanguageProfile.defaultEnglishProfile(USER_ID);
        active.setId(7L);
        when(repository.findByUserIdAndIsActiveTrue(USER_ID)).thenReturn(Optional.of(active));

        assertSame(active, service.ensureDefaultProfile(USER_ID));
        verify(repository, never()).save(any());
    }

    @Test
    void ensureDefaultProfile_CreatesTurkishEnglishB1_WhenUserHasNoProfile() {
        // The backfill covers existing users; a user created after V028 whose first request is
        // a read must still get a profile rather than a 500.
        when(repository.findByUserIdAndIsActiveTrue(USER_ID)).thenReturn(Optional.empty());
        when(repository.findByUserIdOrderByCreatedAtAscIdAsc(USER_ID)).thenReturn(List.of());

        LanguageProfile created = service.ensureDefaultProfile(USER_ID);

        assertEquals(USER_ID, created.getUserId());
        assertEquals("Turkish", created.getSourceLanguage());
        assertEquals("English", created.getTargetLanguage());
        assertEquals("B1", created.getLevel());
        assertNull(created.getLearningGoal());
        assertTrue(created.isActive());
        verify(repository).save(created);
    }

    @Test
    void ensureDefaultProfile_ReturnsTheWinnersProfile_WhenAConcurrentRequestInsertedItFirst() {
        // Two first reads of a brand-new user (the shipped client fires /srs/stats and /words
        // together) both see no profile and both insert; the loser's insert hits the
        // (user_id, target_language) unique key and must read the winner's row, not fail.
        LanguageProfile winner = LanguageProfile.defaultEnglishProfile(USER_ID);
        winner.setId(9L);
        when(repository.findByUserIdAndIsActiveTrue(USER_ID))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(winner));
        when(repository.findByUserIdOrderByCreatedAtAscIdAsc(USER_ID)).thenReturn(List.of());
        when(repository.save(any(LanguageProfile.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("uk_language_profiles_user_target"));

        LanguageProfile result = service.ensureDefaultProfile(USER_ID);

        assertSame(winner, result);
        verify(repository, times(2)).findByUserIdAndIsActiveTrue(USER_ID);
    }

    @Test
    void ensureDefaultProfile_Rethrows_WhenTheUniqueViolationIsNotARace() {
        when(repository.findByUserIdAndIsActiveTrue(USER_ID)).thenReturn(Optional.empty());
        when(repository.findByUserIdOrderByCreatedAtAscIdAsc(USER_ID)).thenReturn(List.of());
        when(repository.findByUserIdAndTargetLanguage(USER_ID, "English")).thenReturn(Optional.empty());
        when(repository.save(any(LanguageProfile.class)))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("fk_language_profiles_user"));

        assertThrows(org.springframework.dao.DataIntegrityViolationException.class,
                () -> service.ensureDefaultProfile(USER_ID));
    }

    @Test
    void ensureDefaultProfile_ActivatesTheOldestProfile_WhenNoneIsActive() {
        LanguageProfile older = new LanguageProfile(USER_ID, "Turkish", "English", "B1", null, false);
        older.setId(1L);
        LanguageProfile newer = new LanguageProfile(USER_ID, "Turkish", "German", "A1", null, false);
        newer.setId(2L);
        when(repository.findByUserIdAndIsActiveTrue(USER_ID)).thenReturn(Optional.empty());
        when(repository.findByUserIdOrderByCreatedAtAscIdAsc(USER_ID)).thenReturn(List.of(older, newer));

        LanguageProfile result = service.ensureDefaultProfile(USER_ID);

        assertSame(older, result);
        assertTrue(older.isActive());
        assertFalse(newer.isActive());
    }

    @Test
    void createProfile_FirstProfileIsActive_LaterOnesAreNot() {
        when(repository.existsByUserIdAndTargetLanguage(USER_ID, "English")).thenReturn(false);
        when(repository.findByUserId(USER_ID)).thenReturn(List.of());
        LanguageProfile first = service.createProfile(USER_ID, "Turkish", "english", null, null);
        assertTrue(first.isActive());
        assertEquals("English", first.getTargetLanguage(), "stored with a capital so the unique key matches");
        assertEquals("B1", first.getLevel(), "level defaults when omitted");

        when(repository.existsByUserIdAndTargetLanguage(USER_ID, "German")).thenReturn(false);
        when(repository.findByUserId(USER_ID)).thenReturn(List.of(first));
        LanguageProfile second = service.createProfile(USER_ID, "Turkish", "German", "a2", "Travel");
        assertFalse(second.isActive(), "adding a language does not silently switch the learner to it");
        assertEquals("A2", second.getLevel());
        assertEquals("Travel", second.getLearningGoal());
    }

    @Test
    void createProfile_RejectsDuplicateTargetLanguage() {
        when(repository.existsByUserIdAndTargetLanguage(USER_ID, "English")).thenReturn(true);

        assertThrows(LanguageProfileService.DuplicateTargetLanguageException.class,
                () -> service.createProfile(USER_ID, "Turkish", "English", "B1", null));
        verify(repository, never()).save(any());
    }

    @Test
    void createProfile_RejectsMissingLanguageAndUnknownLevel() {
        assertThrows(IllegalArgumentException.class,
                () -> service.createProfile(USER_ID, "", "English", "B1", null));
        assertThrows(IllegalArgumentException.class,
                () -> service.createProfile(USER_ID, "Turkish", null, "B1", null));
        when(repository.existsByUserIdAndTargetLanguage(USER_ID, "English")).thenReturn(false);
        assertThrows(IllegalArgumentException.class,
                () -> service.createProfile(USER_ID, "Turkish", "English", "Z9", null));
        verify(repository, never()).save(any());
    }

    @Test
    void updateProfile_ChangesOnlyTheFieldsGiven_AndBlankGoalClearsIt() {
        LanguageProfile profile = new LanguageProfile(USER_ID, "Turkish", "English", "B1", "Exam", true);
        profile.setId(3L);
        when(repository.findByIdAndUserId(3L, USER_ID)).thenReturn(Optional.of(profile));

        service.updateProfile(USER_ID, 3L, "c1", null);
        assertEquals("C1", profile.getLevel());
        assertEquals("Exam", profile.getLearningGoal());

        service.updateProfile(USER_ID, 3L, null, "");
        assertEquals("C1", profile.getLevel());
        assertNull(profile.getLearningGoal());
    }

    @Test
    void updateProfile_OfAnotherUsersProfile_IsNotFound() {
        when(repository.findByIdAndUserId(3L, USER_ID)).thenReturn(Optional.empty());

        assertThrows(NoSuchElementException.class, () -> service.updateProfile(USER_ID, 3L, "B2", null));
    }

    @Test
    void activate_DeactivatesTheOthersFirst_ThenActivatesTheTarget() {
        LanguageProfile target = new LanguageProfile(USER_ID, "Turkish", "German", "A1", null, false);
        target.setId(9L);
        when(repository.findByIdAndUserId(9L, USER_ID)).thenReturn(Optional.of(target));

        LanguageProfile result = service.activate(USER_ID, 9L);

        assertTrue(result.isActive());
        var order = inOrder(repository);
        order.verify(repository).deactivateAllByUserId(USER_ID);
        ArgumentCaptor<LanguageProfile> saved = ArgumentCaptor.forClass(LanguageProfile.class);
        order.verify(repository).save(saved.capture());
        assertTrue(saved.getValue().isActive());
    }

    @Test
    void activate_OnTheActiveProfile_IsANoOp() {
        LanguageProfile target = new LanguageProfile(USER_ID, "Turkish", "English", "B1", null, true);
        target.setId(9L);
        when(repository.findByIdAndUserId(9L, USER_ID)).thenReturn(Optional.of(target));

        assertSame(target, service.activate(USER_ID, 9L));
        verify(repository, never()).deactivateAllByUserId(any());
        verify(repository, never()).save(any());
    }

    @Test
    void activate_UnknownProfile_IsNotFound() {
        when(repository.findByIdAndUserId(9L, USER_ID)).thenReturn(Optional.empty());

        assertThrows(NoSuchElementException.class, () -> service.activate(USER_ID, 9L));
        verify(repository, never()).deactivateAllByUserId(any());
    }

    @Test
    void everyEntryPoint_RejectsAMissingUserId() {
        assertThrows(IllegalArgumentException.class, () -> service.ensureDefaultProfile(null));
        assertThrows(IllegalArgumentException.class, () -> service.listProfiles(0L));
        assertThrows(IllegalArgumentException.class, () -> service.createProfile(null, "Turkish", "English", null, null));
    }
}
