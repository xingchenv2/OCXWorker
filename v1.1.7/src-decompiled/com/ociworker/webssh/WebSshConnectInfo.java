/*
 * Decompiled with CFR 0.152.
 * 
 * Could not load the following classes:
 *  com.fasterxml.jackson.annotation.JsonIgnoreProperties
 *  com.fasterxml.jackson.annotation.JsonProperty
 *  com.ociworker.webssh.WebSshConnectInfo
 *  lombok.Generated
 */
package com.ociworker.webssh;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Generated;

@JsonIgnoreProperties(ignoreUnknown=true)
public class WebSshConnectInfo {
    private String username;
    private String password;
    private String hostname;
    private int port = 22;
    @JsonProperty(value="logintype")
    private int loginType;
    private String privateKey;
    private String passphrase;
    private String proxyHost;
    private int proxyPort;
    private String proxyUser;
    private String proxyPass;

    void normalizeHostname() {
        if (this.hostname != null && this.hostname.contains(":") && !this.hostname.startsWith("[")) {
            this.hostname = "[" + this.hostname + "]";
        }
        if (this.port <= 0) {
            this.port = 22;
        }
    }

    @Generated
    public WebSshConnectInfo() {
    }

    @Generated
    public String getUsername() {
        return this.username;
    }

    @Generated
    public String getPassword() {
        return this.password;
    }

    @Generated
    public String getHostname() {
        return this.hostname;
    }

    @Generated
    public int getPort() {
        return this.port;
    }

    @Generated
    public int getLoginType() {
        return this.loginType;
    }

    @Generated
    public String getPrivateKey() {
        return this.privateKey;
    }

    @Generated
    public String getPassphrase() {
        return this.passphrase;
    }

    @Generated
    public String getProxyHost() {
        return this.proxyHost;
    }

    @Generated
    public int getProxyPort() {
        return this.proxyPort;
    }

    @Generated
    public String getProxyUser() {
        return this.proxyUser;
    }

    @Generated
    public String getProxyPass() {
        return this.proxyPass;
    }

    @Generated
    public void setUsername(String username) {
        this.username = username;
    }

    @Generated
    public void setPassword(String password) {
        this.password = password;
    }

    @Generated
    public void setHostname(String hostname) {
        this.hostname = hostname;
    }

    @Generated
    public void setPort(int port) {
        this.port = port;
    }

    @JsonProperty(value="logintype")
    @Generated
    public void setLoginType(int loginType) {
        this.loginType = loginType;
    }

    @Generated
    public void setPrivateKey(String privateKey) {
        this.privateKey = privateKey;
    }

    @Generated
    public void setPassphrase(String passphrase) {
        this.passphrase = passphrase;
    }

    @Generated
    public void setProxyHost(String proxyHost) {
        this.proxyHost = proxyHost;
    }

    @Generated
    public void setProxyPort(int proxyPort) {
        this.proxyPort = proxyPort;
    }

    @Generated
    public void setProxyUser(String proxyUser) {
        this.proxyUser = proxyUser;
    }

    @Generated
    public void setProxyPass(String proxyPass) {
        this.proxyPass = proxyPass;
    }

    @Generated
    public boolean equals(Object o) {
        if (o == this) {
            return true;
        }
        if (!(o instanceof WebSshConnectInfo)) {
            return false;
        }
        WebSshConnectInfo other = (WebSshConnectInfo)o;
        if (!other.canEqual((Object)this)) {
            return false;
        }
        if (this.getPort() != other.getPort()) {
            return false;
        }
        if (this.getLoginType() != other.getLoginType()) {
            return false;
        }
        if (this.getProxyPort() != other.getProxyPort()) {
            return false;
        }
        String this$username = this.getUsername();
        String other$username = other.getUsername();
        if (this$username == null ? other$username != null : !this$username.equals(other$username)) {
            return false;
        }
        String this$password = this.getPassword();
        String other$password = other.getPassword();
        if (this$password == null ? other$password != null : !this$password.equals(other$password)) {
            return false;
        }
        String this$hostname = this.getHostname();
        String other$hostname = other.getHostname();
        if (this$hostname == null ? other$hostname != null : !this$hostname.equals(other$hostname)) {
            return false;
        }
        String this$privateKey = this.getPrivateKey();
        String other$privateKey = other.getPrivateKey();
        if (this$privateKey == null ? other$privateKey != null : !this$privateKey.equals(other$privateKey)) {
            return false;
        }
        String this$passphrase = this.getPassphrase();
        String other$passphrase = other.getPassphrase();
        if (this$passphrase == null ? other$passphrase != null : !this$passphrase.equals(other$passphrase)) {
            return false;
        }
        String this$proxyHost = this.getProxyHost();
        String other$proxyHost = other.getProxyHost();
        if (this$proxyHost == null ? other$proxyHost != null : !this$proxyHost.equals(other$proxyHost)) {
            return false;
        }
        String this$proxyUser = this.getProxyUser();
        String other$proxyUser = other.getProxyUser();
        if (this$proxyUser == null ? other$proxyUser != null : !this$proxyUser.equals(other$proxyUser)) {
            return false;
        }
        String this$proxyPass = this.getProxyPass();
        String other$proxyPass = other.getProxyPass();
        return !(this$proxyPass == null ? other$proxyPass != null : !this$proxyPass.equals(other$proxyPass));
    }

    @Generated
    protected boolean canEqual(Object other) {
        return other instanceof WebSshConnectInfo;
    }

    @Generated
    public int hashCode() {
        int PRIME = 59;
        int result = 1;
        result = result * 59 + this.getPort();
        result = result * 59 + this.getLoginType();
        result = result * 59 + this.getProxyPort();
        String $username = this.getUsername();
        result = result * 59 + ($username == null ? 43 : $username.hashCode());
        String $password = this.getPassword();
        result = result * 59 + ($password == null ? 43 : $password.hashCode());
        String $hostname = this.getHostname();
        result = result * 59 + ($hostname == null ? 43 : $hostname.hashCode());
        String $privateKey = this.getPrivateKey();
        result = result * 59 + ($privateKey == null ? 43 : $privateKey.hashCode());
        String $passphrase = this.getPassphrase();
        result = result * 59 + ($passphrase == null ? 43 : $passphrase.hashCode());
        String $proxyHost = this.getProxyHost();
        result = result * 59 + ($proxyHost == null ? 43 : $proxyHost.hashCode());
        String $proxyUser = this.getProxyUser();
        result = result * 59 + ($proxyUser == null ? 43 : $proxyUser.hashCode());
        String $proxyPass = this.getProxyPass();
        result = result * 59 + ($proxyPass == null ? 43 : $proxyPass.hashCode());
        return result;
    }

    @Generated
    public String toString() {
        return "WebSshConnectInfo(username=" + this.getUsername() + ", password=" + this.getPassword() + ", hostname=" + this.getHostname() + ", port=" + this.getPort() + ", loginType=" + this.getLoginType() + ", privateKey=" + this.getPrivateKey() + ", passphrase=" + this.getPassphrase() + ", proxyHost=" + this.getProxyHost() + ", proxyPort=" + this.getProxyPort() + ", proxyUser=" + this.getProxyUser() + ", proxyPass=" + this.getProxyPass() + ")";
    }
}

