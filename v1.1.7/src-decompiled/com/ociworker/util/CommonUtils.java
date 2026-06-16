/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  cn.hutool.core.util.IdUtil
 *  cn.hutool.crypto.digest.DigestUtil
 *  com.ociworker.util.CommonUtils
 */
package com.ociworker.util;

import cn.hutool.core.util.IdUtil;
import cn.hutool.crypto.digest.DigestUtil;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;

/*
 * Exception performing whole class analysis ignored.
 */
public class CommonUtils {
    public static final String CREATE_TASK_PREFIX = "create_task_";
    public static final String CHANGE_IP_TASK_PREFIX = "change_ip_task_";
    public static final String BEGIN_CREATE_MESSAGE_TEMPLATE = "\u3010\u5f00\u673a\u4efb\u52a1\u3011\n\n\ud83d\ude80 \u5f00\u59cb\u62a2\u673a \ud83d\ude80\n\u7528\u6237\uff1a%s\n\u65f6\u95f4\uff1a%s\nRegion\uff1a%s\nCPU\u7c7b\u578b\uff1a%s\nCPU\uff1a%s\n\u5185\u5b58\uff08GB\uff09\uff1a%s\n\u78c1\u76d8\u5927\u5c0f\uff08GB\uff09\uff1a%s\n\u5f00\u673a\u6570\u91cf\uff1a%s\nroot\u5bc6\u7801\uff1a%s";
    private static final long TOKEN_EXPIRE_HOURS = 24L;

    public static String generateId() {
        return IdUtil.fastSimpleUUID();
    }

    public static String generateToken(String account, String password) {
        long expireSlot = System.currentTimeMillis() / 86400000L;
        String raw = account + ":" + password + ":" + expireSlot;
        return Base64.getEncoder().encodeToString(DigestUtil.sha256((String)raw));
    }

    public static boolean validateToken(String token, String account, String password) {
        if (token == null || account == null || password == null) {
            return false;
        }
        long currentSlot = System.currentTimeMillis() / 86400000L;
        byte[] tokenBytes = token.getBytes(StandardCharsets.UTF_8);
        for (int i = 0; i <= 1; ++i) {
            String raw = account + ":" + password + ":" + (currentSlot - (long)i);
            String expected = Base64.getEncoder().encodeToString(DigestUtil.sha256((String)raw));
            byte[] expectedBytes = expected.getBytes(StandardCharsets.UTF_8);
            if (!MessageDigest.isEqual(tokenBytes, expectedBytes)) continue;
            return true;
        }
        return false;
    }

    public static String getPwdShell(String password) {
        return CommonUtils.getPwdShell((String)password, null);
    }

    public static String getPwdShell(String password, String customScript) {
        StringBuilder sb = new StringBuilder("#!/bin/bash\n");
        if (password != null && !password.isEmpty()) {
            String chpasswdLine = "root:" + password + "\n";
            String chpasswdB64 = Base64.getEncoder().encodeToString(chpasswdLine.getBytes(StandardCharsets.UTF_8));
            sb.append("set -e\n");
            sb.append("printf '%s' '").append(chpasswdB64).append("' | base64 -d | chpasswd\n");
            sb.append("set +e\n");
            sb.append("OL_SSH_FIX() {\n");
            sb.append("  sed -i -E 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin yes/; ");
            sb.append("s/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' \"$1\" 2>/dev/null || true\n");
            sb.append("}\n");
            sb.append("mkdir -p /etc/ssh/sshd_config.d\n");
            sb.append("if [ -f /etc/ssh/sshd_config ]; then OL_SSH_FIX /etc/ssh/sshd_config; fi\n");
            sb.append("shopt -s nullglob; for f in /etc/ssh/sshd_config.d/*.conf; do ");
            sb.append("OL_SSH_FIX \"$f\"; done; shopt -u nullglob\n");
            sb.append("cat > /etc/ssh/sshd_config.d/99-ociworker.conf <<'SSHEOF'\n");
            sb.append("PermitRootLogin yes\n");
            sb.append("PasswordAuthentication yes\n");
            sb.append("SSHEOF\n");
            sb.append("# zz- \u8986\u76d6 RHEL \u7cfb 5x/99 \u4e2d\u4ecd\u6b8b\u7559\u9879\n");
            sb.append("cat > /etc/ssh/sshd_config.d/zz-ociworker-override.conf <<'SSHEOF2'\n");
            sb.append("PermitRootLogin yes\n");
            sb.append("PasswordAuthentication yes\n");
            sb.append("SSHEOF2\n");
            sb.append("chmod 644 /etc/ssh/sshd_config.d/99-ociworker.conf /etc/ssh/sshd_config.d/zz-ociworker-override.conf 2>/dev/null || true\n");
            sb.append("if getenforce 2>/dev/null | grep -q Enforcing; then restorecon -RFv /etc/ssh /etc/ssh/sshd_config.d 2>/dev/null || true; fi\n");
            sb.append("if sshd -t 2>>/var/log/ociworker-bootstrap.log; then\n");
            sb.append("  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || ");
            sb.append("service sshd restart 2>/dev/null || service ssh restart\n");
            sb.append("else\n");
            sb.append("  echo 'ociworker: sshd -t failed, not restarting ssh' >>/var/log/ociworker-bootstrap.log\n");
            sb.append("fi\n");
        }
        if (customScript != null && !customScript.trim().isEmpty()) {
            sb.append("\n# --- Custom Script ---\n");
            sb.append(customScript.trim()).append("\n");
        }
        return sb.length() > "#!/bin/bash\n".length() ? sb.toString() : "";
    }
}

