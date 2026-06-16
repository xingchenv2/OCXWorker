/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.fasterxml.jackson.databind.ObjectMapper
 *  com.ociworker.webssh.WebSshConnectInfo
 *  com.ociworker.webssh.WebSshConnectInfoParser
 */
package com.ociworker.webssh;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ociworker.webssh.WebSshConnectInfo;
import java.util.Base64;

final class WebSshConnectInfoParser {
    private static final ObjectMapper JSON = new ObjectMapper();

    private WebSshConnectInfoParser() {
    }

    static WebSshConnectInfo parse(String sshInfoB64) throws Exception {
        if (sshInfoB64 == null || sshInfoB64.isBlank()) {
            throw new IllegalArgumentException("sshInfo is empty");
        }
        byte[] decoded = Base64.getDecoder().decode(sshInfoB64.trim());
        WebSshConnectInfo info = (WebSshConnectInfo)JSON.readValue(decoded, WebSshConnectInfo.class);
        info.normalizeHostname();
        return info;
    }
}

