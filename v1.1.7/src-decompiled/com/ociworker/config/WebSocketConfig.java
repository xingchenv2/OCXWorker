/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.ociworker.config.WebSocketConfig
 *  com.ociworker.websocket.LogWebSocketHandler
 *  com.ociworker.webssh.WebSshConsoleTerminalWebSocketHandler
 *  com.ociworker.webssh.WebSshTerminalWebSocketHandler
 *  com.ociworker.webssh.WebSshUploadProgressWebSocketHandler
 *  jakarta.annotation.Resource
 *  org.springframework.context.annotation.Configuration
 *  org.springframework.web.socket.WebSocketHandler
 *  org.springframework.web.socket.config.annotation.EnableWebSocket
 *  org.springframework.web.socket.config.annotation.WebSocketConfigurer
 *  org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry
 */
package com.ociworker.config;

import com.ociworker.websocket.LogWebSocketHandler;
import com.ociworker.webssh.WebSshConsoleTerminalWebSocketHandler;
import com.ociworker.webssh.WebSshTerminalWebSocketHandler;
import com.ociworker.webssh.WebSshUploadProgressWebSocketHandler;
import jakarta.annotation.Resource;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig
implements WebSocketConfigurer {
    @Resource
    private LogWebSocketHandler logWebSocketHandler;
    @Resource
    private WebSshTerminalWebSocketHandler webSshTerminalWebSocketHandler;
    @Resource
    private WebSshConsoleTerminalWebSocketHandler webSshConsoleTerminalWebSocketHandler;
    @Resource
    private WebSshUploadProgressWebSocketHandler webSshUploadProgressWebSocketHandler;

    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler((WebSocketHandler)this.logWebSocketHandler, new String[]{"/ws/log"}).setAllowedOrigins(new String[]{"*"});
        registry.addHandler((WebSocketHandler)this.webSshTerminalWebSocketHandler, new String[]{"/webssh-api/term"}).setAllowedOrigins(new String[]{"*"});
        registry.addHandler((WebSocketHandler)this.webSshConsoleTerminalWebSocketHandler, new String[]{"/webssh-api/console-term"}).setAllowedOrigins(new String[]{"*"});
        registry.addHandler((WebSocketHandler)this.webSshUploadProgressWebSocketHandler, new String[]{"/webssh-api/file/progress"}).setAllowedOrigins(new String[]{"*"});
    }
}

