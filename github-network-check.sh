#!/bin/bash

# GitHub 网络连接诊断工具
# 用于定位 DNS 污染、GFW 封锁等网络问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  GitHub 网络连接诊断工具"
echo "=========================================="
echo ""

# 1. 基础连接测试
echo -e "${BLUE}[1/7] 基础 Ping 测试${NC}"
echo "----------------------------------------"
for host in github.com api.github.com raw.githubusercontent.com; do
    echo -n "  Ping $host: "
    if ping -c 3 -W 5 $host > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 可达${NC}"
    else
        echo -e "${RED}✗ 不可达${NC}"
    fi
done
echo ""

# 2. DNS 解析测试
echo -e "${BLUE}[2/7] DNS 解析测试${NC}"
echo "----------------------------------------"
GITHUB_DOMAINS="github.com api.github.com raw.githubusercontent.com github.githubassets.com"

for domain in $GITHUB_DOMAINS; do
    echo "  $domain:"
    
    # 系统 DNS
    sys_ip=$(dig +short $domain 2>/dev/null | head -1)
    echo "    系统 DNS: ${sys_ip:-解析失败}"
    
    # Google DNS
    google_ip=$(dig +short $domain @8.8.8.8 2>/dev/null | head -1)
    echo "    Google DNS (8.8.8.8): ${google_ip:-解析失败}"
    
    # Cloudflare DNS
    cf_ip=$(dig +short $domain @1.1.1.1 2>/dev/null | head -1)
    echo "    Cloudflare DNS (1.1.1.1): ${cf_ip:-解析失败}"
    
    # 阿里 DNS
    ali_ip=$(dig +short $domain @223.5.5.5 2>/dev/null | head -1)
    echo "    阿里 DNS (223.5.5.5): ${ali_ip:-解析失败}"
    
    # 检查是否被污染到国内 IP
    if [[ "$sys_ip" =~ ^(127\.|0\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        echo -e "    ${RED}⚠ 可能存在 DNS 污染（解析到内网 IP）${NC}"
    fi
    echo ""
done

# 3. HTTPS 连接测试
echo -e "${BLUE}[3/7] HTTPS 连接测试${NC}"
echo "----------------------------------------"
URLS="https://github.com https://api.github.com https://raw.githubusercontent.com"

for url in $URLS; do
    echo -n "  $url: "
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$url" 2>/dev/null)
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        echo -e "${GREEN}✓ HTTP $http_code${NC}"
    elif [ "$http_code" = "000" ]; then
        echo -e "${RED}✗ 连接超时/失败${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP $http_code${NC}"
    fi
done
echo ""

# 4. SSL/TLS 证书验证
echo -e "${BLUE}[4/7] SSL 证书验证${NC}"
echo "----------------------------------------"
for host in github.com api.github.com; do
    echo -n "  $host: "
    cert_info=$(echo | openssl s_client -servername $host -connect $host:443 2>/dev/null | openssl x509 -noout -issuer -dates 2>/dev/null)
    if [ -n "$cert_info" ]; then
        issuer=$(echo "$cert_info" | grep "issuer" | sed 's/issuer=//')
        if [[ "$issuer" == *"DigiCert"* ]] || [[ "$issuer" == *"Microsoft"* ]]; then
            echo -e "${GREEN}✓ 证书正常 (${issuer})${NC}"
        else
            echo -e "${YELLOW}⚠ 证书颁发者异常: $issuer${NC}"
        fi
    else
        echo -e "${RED}✗ 无法获取证书（可能被中间人攻击或连接失败）${NC}"
    fi
done
echo ""

# 5. 路由追踪
echo -e "${BLUE}[5/7] 路由追踪 (前 15 跳)${NC}"
echo "----------------------------------------"
echo "  追踪到 github.com ..."
if command -v traceroute &> /dev/null; then
    traceroute -m 15 -w 2 github.com 2>/dev/null | head -20
else
    echo "  traceroute 命令不可用"
fi
echo ""

# 6. TCP 端口连接测试
echo -e "${BLUE}[6/7] TCP 端口测试${NC}"
echo "----------------------------------------"
PORTS="22 80 443 9418"
for port in $PORTS; do
    echo -n "  github.com:$port - "
    if nc -z -w 5 github.com $port 2>/dev/null; then
        echo -e "${GREEN}✓ 开放${NC}"
    else
        echo -e "${RED}✗ 关闭/被封${NC}"
    fi
done
echo ""

# 7. Git 协议测试
echo -e "${BLUE}[7/7] Git 协议测试${NC}"
echo "----------------------------------------"
echo -n "  HTTPS (git clone): "
timeout 15 git ls-remote https://github.com/git/git.git HEAD > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 正常${NC}"
else
    echo -e "${RED}✗ 失败${NC}"
fi

echo -n "  SSH (git@github.com): "
timeout 15 ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 正常${NC}"
else
    # SSH 返回 1 但显示认证成功也算正常
    ssh_result=$(timeout 15 ssh -T git@github.com 2>&1)
    if [[ "$ssh_result" == *"successfully authenticated"* ]] || [[ "$ssh_result" == *"Hi "* ]]; then
        echo -e "${GREEN}✓ 正常${NC}"
    else
        echo -e "${RED}✗ 失败${NC}"
    fi
fi
echo ""

# 8. 诊断结论
echo "=========================================="
echo -e "${BLUE}  诊断结论与建议${NC}"
echo "=========================================="
echo ""

# 检查代理设置
echo "当前代理设置:"
echo "  http_proxy: ${http_proxy:-未设置}"
echo "  https_proxy: ${https_proxy:-未设置}"
echo "  ALL_PROXY: ${ALL_PROXY:-未设置}"
echo ""

echo "常见解决方案:"
echo "  1. DNS 污染 → 修改 /etc/hosts 或使用 DoH/DoT"
echo "  2. GFW 封锁 → 使用代理 (export https_proxy=...)"
echo "  3. 公司防火墙 → 联系 IT 部门开放 GitHub"
echo "  4. GitHub 镜像 → 使用 gitee/gitclone.com 等"
echo ""

echo "推荐的 /etc/hosts 配置 (如果 DNS 污染):"
echo "  140.82.114.4    github.com"
echo "  140.82.114.3    api.github.com"
echo "  185.199.108.133 raw.githubusercontent.com"
echo "  185.199.108.154 github.githubassets.com"
echo ""
echo "获取最新 IP: https://www.ipaddress.com/website/github.com"
