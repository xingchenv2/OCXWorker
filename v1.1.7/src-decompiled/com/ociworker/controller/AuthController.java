/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  cn.hutool.core.util.RandomUtil
 *  cn.hutool.core.util.StrUtil
 *  cn.hutool.crypto.digest.DigestUtil
 *  com.baomidou.mybatisplus.core.conditions.Wrapper
 *  com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper
 *  com.ociworker.controller.AuthController
 *  com.ociworker.mapper.OciKvMapper
 *  com.ociworker.model.entity.OciKv
 *  com.ociworker.model.params.LoginParams
 *  com.ociworker.model.vo.ResponseData
 *  com.ociworker.service.LoginAuditService
 *  com.ociworker.service.LoginSecurityService
 *  com.ociworker.service.NotificationService
 *  com.ociworker.service.VerifyCodeService
 *  com.ociworker.util.CommonUtils
 *  com.ociworker.util.HttpRequestUtil
 *  jakarta.annotation.Resource
 *  jakarta.servlet.http.HttpServletRequest
 *  jakarta.servlet.http.HttpServletResponse
 *  jakarta.validation.Valid
 *  org.springframework.beans.factory.annotation.Value
 *  org.springframework.http.ResponseCookie
 *  org.springframework.http.ResponseEntity
 *  org.springframework.web.bind.annotation.GetMapping
 *  org.springframework.web.bind.annotation.PostMapping
 *  org.springframework.web.bind.annotation.RequestBody
 *  org.springframework.web.bind.annotation.RequestMapping
 *  org.springframework.web.bind.annotation.RestController
 */
package com.ociworker.controller;

import cn.hutool.core.util.RandomUtil;
import cn.hutool.core.util.StrUtil;
import cn.hutool.crypto.digest.DigestUtil;
import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.ociworker.mapper.OciKvMapper;
import com.ociworker.model.entity.OciKv;
import com.ociworker.model.params.LoginParams;
import com.ociworker.model.vo.ResponseData;
import com.ociworker.service.LoginAuditService;
import com.ociworker.service.LoginSecurityService;
import com.ociworker.service.NotificationService;
import com.ociworker.service.VerifyCodeService;
import com.ociworker.util.CommonUtils;
import com.ociworker.util.HttpRequestUtil;
import jakarta.annotation.Resource;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(value={"/api/auth"})
public class AuthController {
    @Value(value="${web.account}")
    private String defaultAccount;
    @Value(value="${web.password}")
    private String defaultPassword;
    @Resource
    private OciKvMapper kvMapper;
    @Resource
    private NotificationService notificationService;
    @Resource
    private VerifyCodeService verifyCodeService;
    @Resource
    private LoginSecurityService loginSecurityService;
    @Resource
    private LoginAuditService loginAuditService;
    private static final long TG_CODE_EXPIRE_MS = 30000L;
    private static final int TG_CODE_MAX_ATTEMPTS = 3;
    private static final int TG_SEND_BURST_MAX = 3;
    private static final long TG_SEND_BURST_COOLDOWN_MS = 60000L;
    private volatile String tgLoginCode;
    private volatile long tgLoginCodeExpireAt;
    private volatile long tgLoginCodeSentAt;
    private volatile int tgSendBurstCount;
    private final AtomicInteger tgLoginFailCount = new AtomicInteger(0);
    private static final String CODE_ACCOUNT = "web_account";
    private static final String CODE_PASSWORD = "web_password";
    private static final String TYPE = "sys_config";

    private String getKv(String code) {
        OciKv kv = (OciKv)this.kvMapper.selectOne((Wrapper)((LambdaQueryWrapper)new LambdaQueryWrapper().eq(OciKv::getCode, (Object)code)).eq(OciKv::getType, (Object)TYPE));
        return kv != null ? kv.getValue() : null;
    }

    private void setKv(String code, String value) {
        OciKv existing = (OciKv)this.kvMapper.selectOne((Wrapper)((LambdaQueryWrapper)new LambdaQueryWrapper().eq(OciKv::getCode, (Object)code)).eq(OciKv::getType, (Object)TYPE));
        if (existing != null) {
            existing.setValue(value);
            this.kvMapper.updateById((Object)existing);
        } else {
            OciKv kv = new OciKv();
            kv.setId(CommonUtils.generateId());
            kv.setCode(code);
            kv.setValue(value);
            kv.setType(TYPE);
            this.kvMapper.insert((Object)kv);
        }
    }

    private boolean isSetupDone() {
        return this.getKv(CODE_ACCOUNT) != null || this.getKv(CODE_PASSWORD) != null;
    }

    public String getEffectiveAccount() {
        String stored = this.getKv(CODE_ACCOUNT);
        return stored != null ? stored : this.defaultAccount;
    }

    private boolean isHashedPassword(String pwd) {
        return pwd != null && pwd.length() == 64 && pwd.matches("[0-9a-f]+");
    }

    public String getEffectivePasswordHash() {
        String stored = this.getKv(CODE_PASSWORD);
        if (stored != null) {
            if (this.isHashedPassword(stored)) {
                return stored;
            }
            String hashed = DigestUtil.sha256Hex((String)stored);
            this.setKv(CODE_PASSWORD, hashed);
            return hashed;
        }
        return DigestUtil.sha256Hex((String)this.defaultPassword);
    }

    @GetMapping(value={"/needSetup"})
    public ResponseData<?> needSetup() {
        return ResponseData.ok((Object)(!this.isSetupDone() ? 1 : 0));
    }

    @PostMapping(value={"/setup"})
    public ResponseData<?> setup(@RequestBody Map<String, String> params) {
        if (this.isSetupDone()) {
            return ResponseData.error((String)"\u7cfb\u7edf\u5df2\u521d\u59cb\u5316\uff0c\u65e0\u6cd5\u91cd\u590d\u8bbe\u7f6e");
        }
        String account = params.get("account");
        String password = params.get("password");
        if (account == null || account.length() < 3) {
            return ResponseData.error((String)"\u7528\u6237\u540d\u81f3\u5c113\u4e2a\u5b57\u7b26");
        }
        if (password == null || password.length() < 6) {
            return ResponseData.error((String)"\u5bc6\u7801\u81f3\u5c116\u4e2a\u5b57\u7b26");
        }
        this.setKv(CODE_ACCOUNT, account);
        this.setKv(CODE_PASSWORD, DigestUtil.sha256Hex((String)password));
        String token = CommonUtils.generateToken((String)account, (String)DigestUtil.sha256Hex((String)password));
        return ResponseData.ok(Map.of("token", token, "account", account));
    }

    @GetMapping(value={"/device"})
    public ResponseEntity<Void> ensureDeviceCookie(HttpServletRequest request, HttpServletResponse response) {
        String existing = HttpRequestUtil.getCookie((HttpServletRequest)request, (String)"ow_did");
        if (StrUtil.isBlank((CharSequence)existing)) {
            String id = CommonUtils.generateId();
            ResponseCookie cookie = ResponseCookie.from((String)"ow_did", (String)id).httpOnly(true).path("/").maxAge(Duration.ofDays(365L)).sameSite("Lax").build();
            response.addHeader("Set-Cookie", cookie.toString());
        }
        return ResponseEntity.noContent().build();
    }

    @PostMapping(value={"/login"})
    public ResponseData<?> login(@RequestBody @Valid LoginParams params, HttpServletRequest request) {
        String deviceId;
        if (!this.isSetupDone()) {
            return ResponseData.error((int)403, (String)"\u8bf7\u5148\u5b8c\u6210\u521d\u59cb\u5316\u8bbe\u7f6e");
        }
        String ip = HttpRequestUtil.getClientIp((HttpServletRequest)request);
        if (this.loginSecurityService.isDeniedForLogin(ip, deviceId = this.loginSecurityService.readDeviceIdFromRequest(request))) {
            this.loginAuditService.recordPasswordLogin(params.getAccount(), params.getPassword(), ip, deviceId, false, request);
            return ResponseData.error((int)403, (String)"\u8bbf\u95ee\u88ab\u62d2\u7edd");
        }
        String effectiveAccount = this.getEffectiveAccount();
        String effectivePwdHash = this.getEffectivePasswordHash();
        String inputPwdHash = DigestUtil.sha256Hex((String)params.getPassword());
        if (!effectiveAccount.equals(params.getAccount()) || !effectivePwdHash.equals(inputPwdHash)) {
            this.loginAuditService.recordPasswordLogin(params.getAccount(), params.getPassword(), ip, deviceId, false, request);
            this.loginSecurityService.onPasswordLoginFailed(params.getAccount(), ip, deviceId);
            return ResponseData.error((String)"\u8d26\u53f7\u6216\u5bc6\u7801\u9519\u8bef");
        }
        this.loginAuditService.recordPasswordLogin(effectiveAccount, params.getPassword(), ip, deviceId, true, request);
        String token = CommonUtils.generateToken((String)effectiveAccount, (String)effectivePwdHash);
        this.notificationService.sendMessage("login", String.format("\u3010\u767b\u5f55\u901a\u77e5\u3011\u2705 \u767b\u5f55\u6210\u529f\n\u8d26\u53f7: %s\nIP: %s\n\u65f6\u95f4: %s", params.getAccount(), ip, this.nowStr()));
        return ResponseData.ok(Map.of("token", token, "account", effectiveAccount, "expireHours", 24));
    }

    @PostMapping(value={"/tgLoginSendCode"})
    public ResponseData<?> tgLoginSendCode(HttpServletRequest request) {
        long sinceLastSend;
        String deviceId;
        if (!this.verifyCodeService.isTgConfigured()) {
            return ResponseData.error((String)"\u672a\u7ed1\u5b9a Telegram Bot\uff0c\u65e0\u6cd5\u4f7f\u7528\u6b64\u767b\u5f55\u65b9\u5f0f");
        }
        if (!this.isSetupDone()) {
            return ResponseData.error((int)403, (String)"\u8bf7\u5148\u5b8c\u6210\u521d\u59cb\u5316\u8bbe\u7f6e");
        }
        String ip = HttpRequestUtil.getClientIp((HttpServletRequest)request);
        if (this.loginSecurityService.isDeniedForLogin(ip, deviceId = this.loginSecurityService.readDeviceIdFromRequest(request))) {
            return ResponseData.error((int)403, (String)"\u8bbf\u95ee\u88ab\u62d2\u7edd");
        }
        long now = System.currentTimeMillis();
        if (this.tgLoginCodeSentAt > 0L) {
            sinceLastSend = now - this.tgLoginCodeSentAt;
            if (sinceLastSend < 30000L) {
                long wait = (30000L - sinceLastSend) / 1000L;
                return ResponseData.error((String)("\u8bf7\u6c42\u8fc7\u4e8e\u9891\u7e41\uff0c\u8bf7 " + wait + " \u79d2\u540e\u91cd\u8bd5"));
            }
            if (sinceLastSend >= 60000L) {
                this.tgSendBurstCount = 0;
            }
        }
        if (this.tgSendBurstCount >= 3 && (sinceLastSend = now - this.tgLoginCodeSentAt) < 60000L) {
            long wait = Math.max(1L, (60000L - sinceLastSend + 999L) / 1000L);
            return ResponseData.error((String)("\u5df2\u8fde\u7eed\u53d1\u7801 3 \u6b21\uff0c\u8bf7\u7b49\u5f85 " + wait + " \u79d2\u540e\u518d\u8bd5"));
        }
        String numPart = RandomUtil.randomNumbers((int)6);
        String mixPart = RandomUtil.randomString((String)"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789", (int)11);
        String code = numPart + ":" + mixPart;
        this.tgLoginCode = code;
        this.tgLoginCodeExpireAt = now + 30000L;
        this.tgLoginCodeSentAt = now;
        ++this.tgSendBurstCount;
        this.tgLoginFailCount.set(0);
        String html = String.format("Your token: <code>%s</code>\n\n\u8bf7\u5728 <b>30</b> \u79d2\u5185\u4f7f\u7528\u8be5\u9a8c\u8bc1\u7801\u767b\u5f55\n\n<i>IP: %s</i>", code, ip);
        this.notificationService.sendTelegramHtml(html, null);
        return ResponseData.ok(Map.of("message", "\u9a8c\u8bc1\u7801\u5df2\u53d1\u9001\u5230 Telegram"));
    }

    @PostMapping(value={"/tgLogin"})
    public ResponseData<?> tgLogin(@RequestBody Map<String, String> params, HttpServletRequest request) {
        if (!this.verifyCodeService.isTgConfigured()) {
            return ResponseData.error((String)"\u672a\u7ed1\u5b9a Telegram Bot");
        }
        if (!this.isSetupDone()) {
            return ResponseData.error((int)403, (String)"\u8bf7\u5148\u5b8c\u6210\u521d\u59cb\u5316\u8bbe\u7f6e");
        }
        String ip = HttpRequestUtil.getClientIp((HttpServletRequest)request);
        String deviceId = this.loginSecurityService.readDeviceIdFromRequest(request);
        String tgAcct = this.getEffectiveAccount();
        if (this.loginSecurityService.isDeniedForLogin(ip, deviceId)) {
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, "(\u5c01\u7981\u62e6\u622a)");
            return ResponseData.error((int)403, (String)"\u8bbf\u95ee\u88ab\u62d2\u7edd");
        }
        String inputCode = params.get("code");
        if (inputCode == null || inputCode.isBlank()) {
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, "(\u672a\u586b\u9a8c\u8bc1\u7801)");
            return ResponseData.error((String)"\u8bf7\u8f93\u5165\u9a8c\u8bc1\u7801");
        }
        if (this.tgLoginCode == null) {
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, "(\u672a\u83b7\u53d6\u9a8c\u8bc1\u7801)");
            return ResponseData.error((String)"\u8bf7\u5148\u83b7\u53d6\u9a8c\u8bc1\u7801");
        }
        if (System.currentTimeMillis() > this.tgLoginCodeExpireAt) {
            this.tgLoginCode = null;
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, "(\u9a8c\u8bc1\u7801\u8fc7\u671f)");
            return ResponseData.error((String)"\u9a8c\u8bc1\u7801\u5df2\u8fc7\u671f\uff0c\u8bf7\u91cd\u65b0\u83b7\u53d6");
        }
        if (this.tgLoginFailCount.get() >= 3) {
            this.tgLoginCode = null;
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, "(\u9a8c\u8bc1\u9501\u5b9a)");
            this.notificationService.sendMessage(String.format("\u3010\u767b\u5f55\u901a\u77e5\u3011\ud83d\udea8 TG\u9a8c\u8bc1\u7801\u767b\u5f55\u88ab\u9501\u5b9a\n\u8fde\u7eed\u9519\u8bef %d \u6b21\nIP: %s\n\u65f6\u95f4: %s", 3, ip, this.nowStr()));
            return ResponseData.error((String)"\u9a8c\u8bc1\u7801\u9519\u8bef\u6b21\u6570\u8fc7\u591a\uff0c\u5df2\u5931\u6548\uff0c\u8bf7\u91cd\u65b0\u83b7\u53d6");
        }
        if (!this.tgLoginCode.equals(inputCode)) {
            this.loginAuditService.recordTelegramLogin(tgAcct, ip, deviceId, false, request, inputCode.trim());
            int fails = this.tgLoginFailCount.incrementAndGet();
            int remaining = 3 - fails;
            if (remaining <= 0) {
                this.tgLoginCode = null;
                this.notificationService.sendMessage(String.format("\u3010\u767b\u5f55\u901a\u77e5\u3011\ud83d\udea8 TG\u9a8c\u8bc1\u7801\u767b\u5f55\u88ab\u9501\u5b9a\n\u8fde\u7eed\u9519\u8bef %d \u6b21\nIP: %s\n\u65f6\u95f4: %s", 3, ip, this.nowStr()));
                return ResponseData.error((String)"\u9a8c\u8bc1\u7801\u9519\u8bef\u6b21\u6570\u8fc7\u591a\uff0c\u5df2\u5931\u6548");
            }
            return ResponseData.error((String)("\u9a8c\u8bc1\u7801\u9519\u8bef\uff0c\u5269\u4f59 " + remaining + " \u6b21\u5c1d\u8bd5\u673a\u4f1a"));
        }
        this.tgLoginCode = null;
        this.tgLoginFailCount.set(0);
        String effectiveAccount = this.getEffectiveAccount();
        String effectivePwdHash = this.getEffectivePasswordHash();
        String token = CommonUtils.generateToken((String)effectiveAccount, (String)effectivePwdHash);
        this.loginAuditService.recordTelegramLogin(effectiveAccount, ip, deviceId, true, request, "(TG\u9a8c\u8bc1\u7801)");
        this.notificationService.sendMessage("login", String.format("\u3010\u767b\u5f55\u901a\u77e5\u3011\u2705 TG\u9a8c\u8bc1\u7801\u767b\u5f55\u6210\u529f\nIP: %s\n\u65f6\u95f4: %s", ip, this.nowStr()));
        return ResponseData.ok(Map.of("token", token, "account", effectiveAccount, "expireHours", 24));
    }

    @GetMapping(value={"/account"})
    public ResponseData<?> currentAccount() {
        return ResponseData.ok(Map.of("account", this.getEffectiveAccount()));
    }

    @GetMapping(value={"/tgLoginAvailable"})
    public ResponseData<?> tgLoginAvailable() {
        return ResponseData.ok((Object)this.verifyCodeService.isTgConfigured());
    }

    @PostMapping(value={"/verifyPassword"})
    public ResponseData<?> verifyPassword(@RequestBody Map<String, String> params) {
        String pwd = params.get("password");
        if (pwd == null || pwd.isBlank()) {
            return ResponseData.error((String)"\u8bf7\u8f93\u5165\u5bc6\u7801");
        }
        if (!this.getEffectivePasswordHash().equals(DigestUtil.sha256Hex((String)pwd))) {
            return ResponseData.error((String)"\u5bc6\u7801\u9519\u8bef");
        }
        return ResponseData.ok();
    }

    @PostMapping(value={"/changePassword"})
    public ResponseData<?> changePassword(@RequestBody Map<String, String> params, HttpServletRequest request) {
        if (this.verifyCodeService.isTgConfigured()) {
            String code = params.get("verifyCode");
            if (code == null || code.isBlank()) {
                return ResponseData.error((String)"\u8bf7\u8f93\u5165 TG \u9a8c\u8bc1\u7801");
            }
            this.verifyCodeService.verifyCode("changePassword", code);
        }
        String oldPwd = params.get("oldPassword");
        String newPwd = params.get("newPassword");
        if (oldPwd == null || newPwd == null || newPwd.length() < 6) {
            return ResponseData.error((String)"\u65b0\u5bc6\u7801\u4e0d\u80fd\u5c11\u4e8e6\u4f4d");
        }
        String effectivePwdHash = this.getEffectivePasswordHash();
        if (!effectivePwdHash.equals(DigestUtil.sha256Hex((String)oldPwd))) {
            return ResponseData.error((String)"\u539f\u5bc6\u7801\u9519\u8bef");
        }
        String newHash = DigestUtil.sha256Hex((String)newPwd);
        this.setKv(CODE_PASSWORD, newHash);
        String account = this.getEffectiveAccount();
        String newToken = CommonUtils.generateToken((String)account, (String)newHash);
        if (this.verifyCodeService.isTgConfigured()) {
            String ip = HttpRequestUtil.getClientIp((HttpServletRequest)request);
            this.notificationService.sendMessage(String.format("\u3010\u767b\u5f55\u901a\u77e5\u3011\ud83d\udd10 \u9762\u677f\u767b\u5f55\u5bc6\u7801\u5df2\u6210\u529f\u4fee\u6539\n\u8d26\u53f7: %s\nIP: %s\n\u65f6\u95f4: %s\n\n\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u7acb\u5373\u68c0\u67e5\u8d26\u6237\u5b89\u5168\u3002", account, ip, this.nowStr()));
        }
        return ResponseData.ok(Map.of("token", newToken, "account", account, "message", "\u5bc6\u7801\u4fee\u6539\u6210\u529f"));
    }

    private String nowStr() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
    }
}

