/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  cn.hutool.core.util.StrUtil
 *  cn.hutool.crypto.SecureUtil
 *  cn.hutool.crypto.symmetric.AES
 *  com.ociworker.util.OciOpenaiKeyCipher
 */
package com.ociworker.util;

import cn.hutool.core.util.StrUtil;
import cn.hutool.crypto.SecureUtil;
import cn.hutool.crypto.symmetric.AES;
import java.nio.charset.StandardCharsets;

/*
 * Exception performing whole class analysis ignored.
 */
public final class OciOpenaiKeyCipher {
    private static final String KEY_SALT = "ociworker-openai-key-v1:";

    private OciOpenaiKeyCipher() {
    }

    public static String encrypt(String plain, String webPassword) {
        if (StrUtil.isBlank((CharSequence)plain)) {
            return null;
        }
        return OciOpenaiKeyCipher.getAes((String)webPassword).encryptBase64(plain);
    }

    public static String decrypt(String encryptedBase64, String webPassword) {
        if (StrUtil.isBlank((CharSequence)encryptedBase64)) {
            return null;
        }
        return OciOpenaiKeyCipher.getAes((String)webPassword).decryptStr(encryptedBase64);
    }

    public static String maskForDisplay(String plain) {
        if (StrUtil.isBlank((CharSequence)plain)) {
            return "sk-****";
        }
        String k = plain.trim();
        if (k.regionMatches(true, 0, "sk-", 0, 3) && k.length() >= 11) {
            return k.substring(0, 7) + "****" + k.substring(k.length() - 4);
        }
        if (k.length() >= 8) {
            return k.substring(0, 4) + "****" + k.substring(k.length() - 4);
        }
        return "sk-****";
    }

    private static AES getAes(String webPassword) {
        String material = "ociworker-openai-key-v1:" + (webPassword == null ? "" : webPassword);
        byte[] key = SecureUtil.sha256().digest(material.getBytes(StandardCharsets.UTF_8));
        return SecureUtil.aes((byte[])key);
    }
}

