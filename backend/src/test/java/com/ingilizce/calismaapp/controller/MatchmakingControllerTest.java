package com.ingilizce.calismaapp.controller;

import com.corundumstudio.socketio.AckRequest;
import com.corundumstudio.socketio.BroadcastOperations;
import com.corundumstudio.socketio.SocketIOClient;
import com.corundumstudio.socketio.SocketIOServer;
import com.corundumstudio.socketio.listener.ConnectListener;
import com.corundumstudio.socketio.listener.DataListener;
import com.corundumstudio.socketio.listener.DisconnectListener;
import com.ingilizce.calismaapp.service.MatchmakingService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MatchmakingControllerTest {

    private SocketIOServer socketIOServer;
    private MatchmakingService matchmakingService;
    private MatchmakingController controller;
    private Map<String, DataListener<?>> listeners;
    private ConnectListener connectListener;
    private DisconnectListener disconnectListener;

    @BeforeEach
    void setUp() {
        socketIOServer = mock(SocketIOServer.class);
        matchmakingService = mock(MatchmakingService.class);
        controller = new MatchmakingController();
        listeners = new HashMap<>();

        ReflectionTestUtils.setField(controller, "socketIOServer", socketIOServer);
        ReflectionTestUtils.setField(controller, "matchmakingService", matchmakingService);

        doAnswer(invocation -> {
            connectListener = invocation.getArgument(0);
            return null;
        }).when(socketIOServer).addConnectListener(any());
        doAnswer(invocation -> {
            disconnectListener = invocation.getArgument(0);
            return null;
        }).when(socketIOServer).addDisconnectListener(any());
        doAnswer(invocation -> {
            listeners.put(invocation.getArgument(0), invocation.getArgument(2));
            return null;
        }).when(socketIOServer).addEventListener(anyString(), any(), any());
    }

    @Test
    void startRegistersListenersAndStartsServer() {
        controller.startSocketIOServer();

        verify(socketIOServer).addConnectListener(any());
        verify(socketIOServer).addDisconnectListener(any());
        verify(socketIOServer).addEventListener(eq("join_queue"), eq(Map.class), any());
        verify(socketIOServer).addEventListener(eq("leave_queue"), eq(String.class), any());
        verify(socketIOServer).addEventListener(eq("join_room"), eq(Map.class), any());
        verify(socketIOServer).addEventListener(eq("webrtc_offer"), eq(Map.class), any());
        verify(socketIOServer).addEventListener(eq("webrtc_answer"), eq(Map.class), any());
        verify(socketIOServer).addEventListener(eq("webrtc_ice_candidate"), eq(Map.class), any());
        verify(socketIOServer).addEventListener(eq("end_call"), eq(Map.class), any());
        verify(socketIOServer).start();
    }

    @Test
    void connectListenerReadsClientIdentityForLogging() {
        controller.startSocketIOServer();
        SocketIOClient client = client("u1");

        connectListener.onConnect(client);

        verify(client).getSessionId();
        verify(client).getRemoteAddress();
    }

    @Test
    void joinQueueRejectsMissingUserId() throws Exception {
        controller.startSocketIOServer();
        SocketIOClient client = client("anonymous");

        mapListener("join_queue").onData(client, Map.of(), mock(AckRequest.class));

        verify(client).sendEvent(eq("queue_error"), any(Map.class));
    }

    @Test
    void joinQueueStoresWaitingClientAndReturnsQueueStatus() throws Exception {
        controller.startSocketIOServer();
        SocketIOClient client = client("u1");
        when(matchmakingService.joinQueue("u1")).thenReturn(null);
        when(matchmakingService.getQueueSize()).thenReturn(1);

        mapListener("join_queue").onData(client, Map.of("userId", "u1"), mock(AckRequest.class));

        verify(client).set("userId", "u1");
        verify(matchmakingService).joinQueue("u1");
        verify(client).sendEvent(eq("queue_status"), any(Map.class));
    }

    @Test
    void joinQueueNotifiesBothClientsWhenMatchIsFound() throws Exception {
        controller.startSocketIOServer();
        SocketIOClient waitingClient = client("waiting");
        SocketIOClient newClient = client("new");
        MatchmakingService.MatchInfo match =
                new MatchmakingService.MatchInfo("waiting", "new", "room_new_waiting");
        when(matchmakingService.joinQueue("waiting")).thenReturn(null);
        when(matchmakingService.joinQueue("new")).thenReturn(match);

        mapListener("join_queue").onData(waitingClient, Map.of("userId", "waiting"), mock(AckRequest.class));
        mapListener("join_queue").onData(newClient, Map.of("userId", "new"), mock(AckRequest.class));

        verify(newClient).sendEvent(eq("match_found"), any(Map.class));
        verify(waitingClient).sendEvent(eq("match_found"), any(Map.class));
    }

    @Test
    void roomAndWebRtcEventsForwardPayloadsToRoomOperations() throws Exception {
        controller.startSocketIOServer();
        SocketIOClient client = client("u1");
        BroadcastOperations room = mock(BroadcastOperations.class);
        when(client.get("userId")).thenReturn("u1");
        when(socketIOServer.getRoomOperations("room-1")).thenReturn(room);

        mapListener("join_room").onData(client, Map.of("roomId", "room-1"), mock(AckRequest.class));
        mapListener("webrtc_offer").onData(client, Map.of("roomId", "room-1", "offer", "offer-sdp"), mock(AckRequest.class));
        mapListener("webrtc_answer").onData(client, Map.of("roomId", "room-1", "answer", "answer-sdp"), mock(AckRequest.class));
        mapListener("webrtc_ice_candidate").onData(client, Map.of(
                "roomId", "room-1",
                "candidate", "candidate",
                "sdpMid", "0",
                "sdpMLineIndex", 0), mock(AckRequest.class));

        verify(client).joinRoom("room-1");
        verify(room).sendEvent(eq("webrtc_offer"), any(Map.class));
        verify(room).sendEvent(eq("webrtc_answer"), any(Map.class));
        verify(room).sendEvent(eq("webrtc_ice_candidate"), any(Map.class));
    }

    @Test
    void leaveAndEndCallCleanUpMatchmakingState() throws Exception {
        controller.startSocketIOServer();
        SocketIOClient client = client("u1");
        BroadcastOperations room = mock(BroadcastOperations.class);
        when(client.get("userId")).thenReturn("u1");
        when(socketIOServer.getRoomOperations("room-1")).thenReturn(room);

        stringListener("leave_queue").onData(client, "", mock(AckRequest.class));
        mapListener("end_call").onData(client, Map.of("roomId", "room-1"), mock(AckRequest.class));

        verify(matchmakingService).leaveQueue("u1");
        verify(matchmakingService).endMatch("u1");
        verify(room).sendEvent("call_ended");
    }

    @Test
    void disconnectEndsActiveMatchAndNotifiesPeer() {
        controller.startSocketIOServer();
        SocketIOClient client = client("u1");
        SocketIOClient peer = client("u2");
        MatchmakingService.MatchInfo match =
                new MatchmakingService.MatchInfo("u1", "u2", "room_u1_u2");
        when(client.get("userId")).thenReturn("u1");
        when(matchmakingService.getMatch("u1")).thenReturn(match);

        @SuppressWarnings("unchecked")
        Map<String, SocketIOClient> clientMap =
                (Map<String, SocketIOClient>) ReflectionTestUtils.getField(controller, "userIdToClient");
        clientMap.put("u2", peer);

        disconnectListener.onDisconnect(client);

        verify(peer).leaveRoom("room_u1_u2");
        verify(peer).sendEvent("call_ended");
        verify(matchmakingService).endMatch("u1");
        verify(matchmakingService).leaveQueue("u1");
    }

    @Test
    void stopDelegatesToSocketServer() {
        controller.stopSocketIOServer();

        verify(socketIOServer).stop();
    }

    @SuppressWarnings("unchecked")
    private DataListener<Map> mapListener(String eventName) {
        return (DataListener<Map>) listeners.get(eventName);
    }

    @SuppressWarnings("unchecked")
    private DataListener<String> stringListener(String eventName) {
        return (DataListener<String>) listeners.get(eventName);
    }

    private static SocketIOClient client(String id) {
        SocketIOClient client = mock(SocketIOClient.class);
        when(client.getSessionId()).thenReturn(UUID.nameUUIDFromBytes(id.getBytes()));
        when(client.getRemoteAddress()).thenReturn(new InetSocketAddress("127.0.0.1", 9000));
        return client;
    }
}
