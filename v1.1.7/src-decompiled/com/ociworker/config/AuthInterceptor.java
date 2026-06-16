/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  cn.hutool.core.util.StrUtil
 *  cn.hutool.crypto.digest.DigestUtil
 *  com.baomidou.mybatisplus.core.conditions.Wrapper
 *  com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper
 *  com.fasterxml.jackson.databind.ObjectMapper
 *  com.ociworker.config.AuthInterceptor
 *  com.ociworker.mapper.OciKvMapper
 *  com.ociworker.model.entity.OciKv
 *  com.ociworker.model.vo.ResponseData
 *  com.ociworker.service.LoginSecurityService
 *  com.ociworker.util.CommonUtils
 *  com.ociworker.util.HttpRequestUtil
 *  jakarta.annotation.Resource
 *  jakarta.servlet.http.HttpServletRequest
 *  jakarta.servlet.http.HttpServletResponse
 *  org.springframework.beans.factory.annotation.Value
 *  org.springframework.stereotype.Component
 *  org.springframework.web.servlet.HandlerInterceptor
 */
package com.ociworker.config;

import cn.hutool.core.util.StrUtil;
import cn.hutool.crypto.digest.DigestUtil;
import com.baomidou.mybatisplus.core.conditions.Wrapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ociworker.mapper.OciKvMapper;
import com.ociworker.model.entity.OciKv;
import com.ociworker.model.vo.ResponseData;
import com.ociworker.service.LoginSecurityService;
import com.ociworker.util.CommonUtils;
import com.ociworker.util.HttpRequestUtil;
import jakarta.annotation.Resource;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
public class AuthInterceptor
implements HandlerInterceptor {
    @Value(value="${web.account}")
    private String defaultAccount;
    @Value(value="${web.password}")
    private String defaultPassword;
    @Resource
    private OciKvMapper kvMapper;
    @Resource
    private LoginSecurityService loginSecurityService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    private String getKv(String code) {
        try {
            OciKv kv = (OciKv)this.kvMapper.selectOne((Wrapper)((LambdaQueryWrapper)new LambdaQueryWrapper().eq(OciKv::getCode, (Object)code)).eq(OciKv::getType, (Object)"sys_config"));
            return kv != null ? kv.getValue() : null;
        }
        catch (Exception e) {
            return null;
        }
    }

    private String getEffectiveAccount() {
        String stored = this.getKv("web_account");
        return stored != null ? stored : this.defaultAccount;
    }

    private boolean isHashedPassword(String pwd) {
        return pwd != null && pwd.length() == 64 && pwd.matches("[0-9a-f]+");
    }

    private String getEffectivePasswordHash() {
        String stored = this.getKv("web_password");
        if (stored != null) {
            if (this.isHashedPassword(stored)) {
                return stored;
            }
            return DigestUtil.sha256Hex((String)stored);
        }
        return DigestUtil.sha256Hex((String)this.defaultPassword);
    }

    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String deviceId;
        String did;
        String ip;
        String uri = request.getRequestURI();
        if (this.loginSecurityService.isSitePaused() && !this.loginSecurityService.isExemptFromSitePause(uri)) {
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(503);
            response.getWriter().write(this.objectMapper.writeValueAsString((Object)ResponseData.error((int)503, (String)"\u7ad9\u70b9\u5df2\u6682\u505c\u8bbf\u95ee\u3002\u8bf7\u901a\u8fc7 Telegram \u4e2d\u7684\u300c\u6062\u590d\u5168\u7ad9\u8bbf\u95ee\u300d\u6216\u4fee\u6539\u6570\u636e\u5e93\u914d\u7f6e\u9879 site_access_paused \u540e\u91cd\u8bd5\u3002")));
            return false;
        }
        if (this.loginSecurityService.isLoginHardenedPath(uri) && this.loginSecurityService.isDeniedForLogin(ip = HttpRequestUtil.getClientIp((HttpServletRequest)request), did = this.loginSecurityService.readDeviceIdFromRequest(request))) {
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(403);
            response.getWriter().write(this.objectMapper.writeValueAsString((Object)ResponseData.error((int)403, (String)"\u8bbf\u95ee\u88ab\u62d2\u7edd")));
            return false;
        }
        if (uri.startsWith("/api/auth/login") || uri.startsWith("/api/auth/needSetup") || uri.startsWith("/api/auth/setup") || uri.startsWith("/api/auth/tgLogin") || uri.startsWith("/api/auth/tgLoginAvailable") || uri.startsWith("/api/auth/device") || uri.startsWith("/ws/") || uri.equals("/") || uri.startsWith("/assets/") || uri.endsWith(".html") || uri.endsWith(".js") || uri.endsWith(".css") || uri.endsWith(".ico") || uri.startsWith("/ip-info")) {
            return true;
        }
        String token = request.getHeader("Authorization");
        if (StrUtil.isBlank((CharSequence)token)) {
            token = request.getParameter("token");
        }
        if (token != null && token.startsWith("Bearer ")) {
            token = token.substring(7).trim();
        }
        String effectiveAccount = this.getEffectiveAccount();
        String effectivePwdHash = this.getEffectivePasswordHash();
        if (StrUtil.isBlank((CharSequence)token) || !CommonUtils.validateToken((String)token, (String)effectiveAccount, (String)effectivePwdHash)) {
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(401);
            response.getWriter().write(this.objectMapper.writeValueAsString((Object)ResponseData.error((int)401, (String)"Unauthorized")));
            return false;
        }
        String clientIp = HttpRequestUtil.getClientIp((HttpServletRequest)request);
        if (this.loginSecurityService.isDeniedForLogin(clientIp, deviceId = this.loginSecurityService.readDeviceIdFromRequest(request))) {
            response.setContentType("application/json;charset=UTF-8");
            response.setStatus(403);
            response.getWriter().write(this.objectMapper.writeValueAsString((Object)ResponseData.error((int)403, (String)"\u8bbf\u95ee\u88ab\u62d2\u7edd")));
            return false;
        }
        return true;
    }
}

