package com.ingilizce.calismaapp.repository;

import com.ingilizce.calismaapp.entity.DevicePushToken;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DevicePushTokenRepository extends JpaRepository<DevicePushToken, Long> {
    Optional<DevicePushToken> findByToken(String token);

    List<DevicePushToken> findByUserIdAndEnabledTrue(Long userId);

    List<DevicePushToken> findByEnabledTrueAndDailyRemindersEnabledTrue(Pageable pageable);

    Optional<DevicePushToken> findByUserIdAndToken(Long userId, String token);
}
