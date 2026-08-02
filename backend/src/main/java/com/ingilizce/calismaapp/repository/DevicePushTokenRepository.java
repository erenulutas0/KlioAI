package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface DevicePushTokenRepository extends JpaRepository<DevicePushToken, Long> {
    Optional<DevicePushToken> findByToken(String token);

    List<DevicePushToken> findByUserId(Long userId);

    List<DevicePushToken> findByUserIdAndEnabledTrue(Long userId);

    /**
     * Devices whose owner has daily reminders switched on.
     *
     * <p>Reads {@code notification_preferences}, which is where the settings screen writes,
     * rather than the copy of the same flag on the token row.
     *
     * <p>Those two had drifted apart and the send path was reading the wrong one. Toggling
     * "daily reminders" in the app updates the preference; the token column is only written
     * when a device registers, and registration is skipped when the token, day and app
     * version are all unchanged. So a learner could switch reminders on, see the switch stay
     * on, and never receive anything — the scheduler was querying a column nothing had
     * updated since install. The production symptom was {@code considered=0} on every run,
     * hour after hour, with no error anywhere.
     *
     * <p>The token column is kept in sync too, so it stops being a lie, but nothing decides
     * delivery from it any more.
     */
    @Query("SELECT t FROM DevicePushToken t WHERE t.enabled = true AND EXISTS ("
            + "SELECT 1 FROM NotificationPreference p "
            + "WHERE p.userId = t.userId AND p.dailyRemindersEnabled = true)")
    List<DevicePushToken> findRemindableTokens(Pageable pageable);

    Optional<DevicePushToken> findByUserIdAndToken(Long userId, String token);
}
