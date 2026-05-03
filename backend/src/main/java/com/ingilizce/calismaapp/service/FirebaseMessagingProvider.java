package com.ingilizce.calismaapp.service;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.ingilizce.calismaapp.config.PushNotificationProperties;
import java.io.ByteArrayInputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

@Component
public class FirebaseMessagingProvider {

    private static final Logger logger = LoggerFactory.getLogger(FirebaseMessagingProvider.class);
    private static final String APP_NAME = "klioai-push";

    private final PushNotificationProperties properties;
    private FirebaseMessaging messaging;
    private boolean initializationAttempted;

    public FirebaseMessagingProvider(PushNotificationProperties properties) {
        this.properties = properties;
    }

    public synchronized Optional<FirebaseMessaging> getMessaging() {
        if (messaging != null) {
            return Optional.of(messaging);
        }
        if (initializationAttempted) {
            return Optional.empty();
        }
        initializationAttempted = true;

        PushNotificationProperties.Firebase firebase = properties.getFirebase();
        if (!firebase.isEnabled()) {
            logger.info("Firebase push notifications are disabled");
            return Optional.empty();
        }

        try (InputStream credentials = openCredentials(firebase)) {
            if (credentials == null) {
                logger.warn("Firebase push notifications enabled but no service account was configured");
                return Optional.empty();
            }

            FirebaseApp app = findExistingApp()
                    .orElseGet(() -> initializeApp(credentials));
            messaging = FirebaseMessaging.getInstance(app);
            logger.info("Firebase push notifications initialized");
            return Optional.of(messaging);
        } catch (Exception ex) {
            logger.error("Firebase push notification initialization failed", ex);
            return Optional.empty();
        }
    }

    private Optional<FirebaseApp> findExistingApp() {
        return FirebaseApp.getApps().stream()
                .filter(app -> APP_NAME.equals(app.getName()))
                .findFirst();
    }

    private FirebaseApp initializeApp(InputStream credentials) {
        try {
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(credentials))
                    .build();
            return FirebaseApp.initializeApp(options, APP_NAME);
        } catch (IOException ex) {
            throw new IllegalStateException("Unable to read Firebase credentials", ex);
        }
    }

    private InputStream openCredentials(PushNotificationProperties.Firebase firebase) throws IOException {
        String json = safe(firebase.getServiceAccountJson());
        if (!json.isEmpty()) {
            return new ByteArrayInputStream(json.getBytes(StandardCharsets.UTF_8));
        }

        String path = safe(firebase.getServiceAccountFile());
        if (!path.isEmpty()) {
            return new FileInputStream(path);
        }

        return null;
    }

    private String safe(String value) {
        return value == null ? "" : value.trim();
    }
}
