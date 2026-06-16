/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  cn.hutool.core.util.StrUtil
 *  cn.hutool.json.JSONUtil
 *  com.baomidou.mybatisplus.core.conditions.Wrapper
 *  com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper
 *  com.baomidou.mybatisplus.core.metadata.IPage
 *  com.baomidou.mybatisplus.extension.plugins.pagination.Page
 *  com.ociworker.mapper.OciLoginAuditMapper
 *  com.ociworker.model.entity.OciLoginAudit
 *  com.ociworker.service.LoginAuditService
 *  com.ociworker.service.LoginAuditService$ParsedUa
 *  com.ociworker.util.CommonUtils
 *  com.ociworker.util.HttpRequestUtil
 *  jakarta.annotation.Resource
 *  jakarta.servlet.http.HttpServletRequest
 *  lombok.Generated
 *  org.slf4j.Logger
 *  org.slf4j.LoggerFactory
 *  org.springframework.scheduling.annotation.Scheduled
 *  org.springframework.stereotype.Service
 *  org.springframework.web.util.ContentCachingRequestWrapper
 */
package com.ociworker.service;

import cn.hutool.core.util.StrUtil;
import cn.hutool.json.JSONUtil;
import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.ociworker.mapper.OciLoginAuditMapper;
import com.ociworker.model.entity.OciLoginAudit;
import com.ociworker.service.LoginAuditService;
import com.ociworker.util.CommonUtils;
import com.ociworker.util.HttpRequestUtil;
import jakarta.annotation.Resource;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.AbstractMap;
import java.util.Collections;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.TreeMap;
import lombok.Generated;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.util.ContentCachingRequestWrapper;

/*
 * Exception performing whole class analysis ignored.
 */
@Service
public class LoginAuditService {
    @Generated
    private static final Logger log = LoggerFactory.getLogger(LoginAuditService.class);
    private static final int PASSWORD_FIELD_MAX = 500;
    private static final int LOGIN_DETAIL_JSON_MAX = 15500000;
    private static final int SINGLE_HEADER_VALUE_MAX = 524288;
    @Resource
    private OciLoginAuditMapper loginAuditMapper;

    public static ParsedUa parseUserAgent(String ua) {
        if (ua == null || ua.isBlank()) {
            return new ParsedUa("\u672a\u77e5", "\u672a\u77e5");
        }
        String u = ua.toLowerCase(Locale.ROOT);
        String os = "\u672a\u77e5";
        if (u.contains("windows")) {
            os = "Windows";
        } else if (u.contains("android")) {
            os = "Android";
        } else if (u.contains("iphone") || u.contains("ipad") || u.contains("ios")) {
            os = "iOS";
        } else if (u.contains("mac os") || u.contains("macintosh")) {
            os = "macOS";
        } else if (u.contains("linux")) {
            os = "Linux";
        }
        String browser = "\u672a\u77e5";
        if (u.contains("edg/")) {
            browser = "Edge";
        } else if (u.contains("opr/") || u.contains("opera")) {
            browser = "Opera";
        } else if (u.contains("firefox/")) {
            browser = "Firefox";
        } else if (u.contains("chrome/") || u.contains("crios/")) {
            browser = "Chrome";
        } else if (u.contains("safari/") && !u.contains("chrome")) {
            browser = "Safari";
        }
        return new ParsedUa(os, browser);
    }

    public void recordPasswordLogin(String account, String passwordPlain, String ip, String deviceId, boolean success, HttpServletRequest request) {
        String ua = request != null ? request.getHeader("User-Agent") : null;
        this.insertRow(account, passwordPlain, ip, deviceId, success, ua, "password", request);
    }

    public void recordTelegramLogin(String account, String ip, String deviceId, boolean success, HttpServletRequest request, String passwordPlaceholder) {
        String ua = request != null ? request.getHeader("User-Agent") : null;
        this.insertRow(account, passwordPlaceholder, ip, deviceId, success, ua, "telegram", request);
    }

    private void insertRow(String account, String passwordPlain, String ip, String deviceId, boolean success, String userAgent, String channel, HttpServletRequest request) {
        try {
            ParsedUa p = LoginAuditService.parseUserAgent((String)userAgent);
            OciLoginAudit row = new OciLoginAudit();
            row.setId(CommonUtils.generateId());
            row.setAccount(StrUtil.trimToNull((CharSequence)account));
            row.setPasswordAttempt(LoginAuditService.truncatePwd((String)passwordPlain));
            row.setIp(ip != null ? ip.trim() : null);
            row.setSuccess(Boolean.valueOf(success));
            row.setDeviceId(StrUtil.trimToNull((CharSequence)deviceId));
            row.setOsName(p.os());
            row.setBrowserName(p.browser());
            row.setLoginChannel(channel);
            row.setUserAgent(userAgent != null && userAgent.length() > 2000 ? userAgent.substring(0, 2000) : userAgent);
            row.setLoginDetail(LoginAuditService.buildLoginDetailJson((HttpServletRequest)request));
            row.setCreateTime(LocalDateTime.now());
            this.loginAuditMapper.insert((Object)row);
        }
        catch (Exception e) {
            log.warn("[LoginAudit] insert skipped: {}", (Object)e.getMessage());
        }
    }

    private static String buildLoginDetailJson(HttpServletRequest req) {
        if (req == null) {
            return null;
        }
        try {
            LinkedHashMap<String, AbstractMap> root = new LinkedHashMap<String, AbstractMap>();
            LinkedHashMap<String, String> entry = new LinkedHashMap<String, String>();
            entry.put("Method", LoginAuditService.nz((String)req.getMethod()));
            entry.put("RequestURI", LoginAuditService.nz((String)req.getRequestURI()));
            entry.put("QueryString", LoginAuditService.nz((String)req.getQueryString()));
            entry.put("Content-Type", LoginAuditService.nz((String)req.getContentType()));
            entry.put("CharacterEncoding", LoginAuditService.nz((String)req.getCharacterEncoding()));
            entry.put("Host", LoginAuditService.nz((String)req.getHeader("Host")));
            entry.put("X-Forwarded-Host", LoginAuditService.nz((String)req.getHeader("X-Forwarded-Host")));
            entry.put("X-Forwarded-Proto", LoginAuditService.nz((String)req.getHeader("X-Forwarded-Proto")));
            entry.put("Origin", LoginAuditService.nz((String)req.getHeader("Origin")));
            entry.put("Referer", LoginAuditService.nz((String)req.getHeader("Referer")));
            root.put("\u8bbf\u95ee\u5165\u53e3", entry);
            LinkedHashMap<String, String> net = new LinkedHashMap<String, String>();
            net.put("X-Forwarded-For", LoginAuditService.nz((String)req.getHeader("X-Forwarded-For")));
            net.put("X-Real-IP", LoginAuditService.nz((String)req.getHeader("X-Real-IP")));
            net.put("Forwarded", LoginAuditService.nz((String)req.getHeader("Forwarded")));
            net.put("Via", LoginAuditService.nz((String)req.getHeader("Via")));
            net.put("Proxy-Connection", LoginAuditService.nz((String)req.getHeader("Proxy-Connection")));
            net.put("CF-Ray", LoginAuditService.nz((String)req.getHeader("CF-Ray")));
            net.put("CF-Connecting-IP", LoginAuditService.nz((String)req.getHeader("CF-Connecting-IP")));
            net.put("CF-Visitor", LoginAuditService.nz((String)req.getHeader("CF-Visitor")));
            net.put("True-Client-IP", LoginAuditService.nz((String)req.getHeader("True-Client-IP")));
            net.put("X-Request-Id", LoginAuditService.nz((String)req.getHeader("X-Request-Id")));
            net.put("X-Correlation-Id", LoginAuditService.nz((String)req.getHeader("X-Correlation-Id")));
            net.put("X-Amzn-Trace-Id", LoginAuditService.nz((String)req.getHeader("X-Amzn-Trace-Id")));
            net.put("Fastly-Client-IP", LoginAuditService.nz((String)req.getHeader("Fastly-Client-IP")));
            net.put("Fly-Client-IP", LoginAuditService.nz((String)req.getHeader("Fly-Client-IP")));
            net.put("RemoteAddr", LoginAuditService.nz((String)req.getRemoteAddr()));
            net.put("RemotePort", String.valueOf(req.getRemotePort()));
            net.put("LocalAddr", LoginAuditService.nz((String)req.getLocalAddr()));
            net.put("LocalPort", String.valueOf(req.getLocalPort()));
            net.put("Protocol", LoginAuditService.nz((String)req.getProtocol()));
            root.put("\u7f51\u7edc\u4e0e\u94fe\u8def", net);
            LinkedHashMap<String, String> fetch = new LinkedHashMap<String, String>();
            fetch.put("Sec-Fetch-Site", LoginAuditService.nz((String)req.getHeader("Sec-Fetch-Site")));
            fetch.put("Sec-Fetch-Mode", LoginAuditService.nz((String)req.getHeader("Sec-Fetch-Mode")));
            fetch.put("Sec-Fetch-Dest", LoginAuditService.nz((String)req.getHeader("Sec-Fetch-Dest")));
            fetch.put("Sec-Fetch-User", LoginAuditService.nz((String)req.getHeader("Sec-Fetch-User")));
            fetch.put("Sec-Fetch-Priority", LoginAuditService.nz((String)req.getHeader("Sec-Fetch-Priority")));
            root.put("Fetch \u5143\u6570\u636e", fetch);
            LinkedHashMap<String, String> hints = new LinkedHashMap<String, String>();
            hints.put("Sec-CH-UA", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA")));
            hints.put("Sec-CH-UA-Full-Version-List", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Full-Version-List")));
            hints.put("Sec-CH-UA-Platform", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Platform")));
            hints.put("Sec-CH-UA-Platform-Version", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Platform-Version")));
            hints.put("Sec-CH-UA-Mobile", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Mobile")));
            hints.put("Sec-CH-UA-Model", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Model")));
            hints.put("Sec-CH-UA-Arch", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Arch")));
            hints.put("Sec-CH-UA-Bitness", LoginAuditService.nz((String)req.getHeader("Sec-CH-UA-Bitness")));
            hints.put("Sec-CH-Viewport-Width", LoginAuditService.nz((String)req.getHeader("Sec-CH-Viewport-Width")));
            hints.put("Viewport-Width", LoginAuditService.nz((String)req.getHeader("Viewport-Width")));
            hints.put("Device-Memory", LoginAuditService.nz((String)req.getHeader("Device-Memory")));
            hints.put("DPR", LoginAuditService.nz((String)req.getHeader("DPR")));
            hints.put("Downlink", LoginAuditService.nz((String)req.getHeader("Downlink")));
            hints.put("RTT", LoginAuditService.nz((String)req.getHeader("RTT")));
            hints.put("ECT", LoginAuditService.nz((String)req.getHeader("ECT")));
            hints.put("Save-Data", LoginAuditService.nz((String)req.getHeader("Save-Data")));
            root.put("Client Hints", hints);
            LinkedHashMap<String, String> client = new LinkedHashMap<String, String>();
            client.put("Accept-Language", LoginAuditService.nz((String)req.getHeader("Accept-Language")));
            client.put("Accept-Encoding", LoginAuditService.nz((String)req.getHeader("Accept-Encoding")));
            client.put("Accept", LoginAuditService.nz((String)req.getHeader("Accept")));
            client.put("User-Agent", LoginAuditService.nz((String)req.getHeader("User-Agent")));
            String did = HttpRequestUtil.getCookie((HttpServletRequest)req, (String)"ow_did");
            client.put("\u8bbe\u5907Cookie(ow_did)\u5df2\u643a\u5e26", StrUtil.isNotBlank((CharSequence)did) ? "\u662f" : "\u5426");
            client.put("ow_did(\u660e\u6587)", LoginAuditService.nz((String)did));
            root.put("\u5ba2\u6237\u7aef\u4e0e\u80fd\u529b", client);
            TreeMap<String, String> allHeaders = new TreeMap<String, String>();
            Enumeration names = req.getHeaderNames();
            if (names != null) {
                for (String hn : Collections.list(names)) {
                    if (hn == null) continue;
                    String v = req.getHeader(hn);
                    allHeaders.put(hn, LoginAuditService.truncPlain((String)v, (int)524288));
                }
            }
            root.put("\u5168\u90e8\u8bf7\u6c42\u5934\uff08\u660e\u6587\uff09", allHeaders);
            LinkedHashMap<String, String> raw = new LinkedHashMap<String, String>();
            raw.put("Cookie", LoginAuditService.nz((String)req.getHeader("Cookie")));
            raw.put("Authorization", LoginAuditService.nz((String)req.getHeader("Authorization")));
            raw.put("RequestBody", LoginAuditService.readCachedRequestBody((HttpServletRequest)req));
            root.put("\u8bf7\u6c42\u539f\u6587\uff08\u9ad8\u654f\u611f\uff09", raw);
            String json = JSONUtil.toJsonStr(root);
            if (json.length() > 15500000) {
                return json.substring(0, 15500000) + "\u2026(login_detail JSON \u8d85\u957f\u5df2\u622a\u65ad)";
            }
            return json;
        }
        catch (Exception e) {
            log.warn("[LoginAudit] buildLoginDetailJson: {}", (Object)e.getMessage());
            return null;
        }
    }

    private static String readCachedRequestBody(HttpServletRequest req) {
        if (!(req instanceof ContentCachingRequestWrapper)) {
            return "";
        }
        ContentCachingRequestWrapper w = (ContentCachingRequestWrapper)req;
        byte[] buf = w.getContentAsByteArray();
        if (buf == null || buf.length == 0) {
            return "";
        }
        Charset cs = StandardCharsets.UTF_8;
        String enc = req.getCharacterEncoding();
        if (enc != null && !enc.isBlank()) {
            try {
                cs = Charset.forName(enc.trim());
            }
            catch (Exception exception) {
                // empty catch block
            }
        }
        return new String(buf, cs);
    }

    private static String truncPlain(String s, int max) {
        if (s == null) {
            return "";
        }
        if (s.length() <= max) {
            return s;
        }
        return s.substring(0, max) + "\u2026(\u8d85\u957f\u5df2\u622a\u65ad)";
    }

    private static String nz(String s) {
        return s == null ? "" : s.trim();
    }

    private static String truncatePwd(String p) {
        if (p == null) {
            return null;
        }
        if (p.length() <= 500) {
            return p;
        }
        return p.substring(0, 500);
    }

    public IPage<OciLoginAudit> pageAudits(long current, long size) {
        return this.loginAuditMapper.selectPage((IPage)new Page(current, size), (Wrapper)new LambdaQueryWrapper().orderByDesc(OciLoginAudit::getCreateTime));
    }

    @Scheduled(cron="0 0 3 * * ?")
    public void purgeOlderThanSevenDays() {
        try {
            LocalDateTime cutoff = LocalDateTime.now().minusDays(7L);
            int n = this.loginAuditMapper.delete((Wrapper)new LambdaQueryWrapper().lt(OciLoginAudit::getCreateTime, (Object)cutoff));
            if (n > 0) {
                log.info("[LoginAudit] purged {} rows older than 7 days", (Object)n);
            }
        }
        catch (Exception e) {
            log.warn("[LoginAudit] purge failed (\u8868\u53ef\u80fd\u5c1a\u672a\u521b\u5efa): {}", (Object)e.getMessage());
        }
    }
}

