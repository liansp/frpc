#!/usr/bin/env bash
set -euo pipefail

# fonts color
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"
# fonts color

# variable
FRP_NAME=frpc
FRP_VERSION=0.65.0
FRP_PATH=/usr/local/frp
SYSTEMD_PATH=/etc/systemd/system
PROXY_URL="https://ghfast.top/"

# ensure we have a sudo helper if not root
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# check network (quick)
GOOGLE_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "https://www.google.com" || echo "")
PROXY_HTTP_CODE=$(curl -o /dev/null --connect-timeout 5 --max-time 8 -s --head -w "%{http_code}" "${PROXY_URL}" || echo "")

# check arch
UNAME_M=$(uname -m || true)
case "${UNAME_M}" in
    x86_64) PLATFORM=amd64 ;;
    aarch64) PLATFORM=arm64 ;;
    armv7|armv7l|armhf) PLATFORM=arm ;;
    *) 
        echo -e "${Red}Unsupported architecture: ${UNAME_M}${Font}"
        exit 1
        ;;
esac

FRP_FILE_NAME="frp_${FRP_VERSION}_linux_${PLATFORM}"
TAR_FILE="${FRP_FILE_NAME}.tar.gz"

# helper download function (curl preferred)
download_file() {
    local url="$1"
    local out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L --connect-timeout 10 --max-time 300 -o "${out}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 -O "${out}" "${url}"
    else
        echo -e "${Red}Neither curl nor wget is available to download files.${Font}"
        return 1
    fi
}

# download (try github direct, then proxy)
DOWNLOAD_OK=0
GITHUB_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TAR_FILE}"
PROXYED_URL="${PROXY_URL}https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TAR_FILE}"

echo -e "${Green}Downloading ${FRP_FILE_NAME}...${Font}"
if [ "${GOOGLE_HTTP_CODE}" = "200" ] && download_file "${GITHUB_URL}" "${TAR_FILE}"; then
    DOWNLOAD_OK=1
else
    if [ "${PROXY_HTTP_CODE}" = "200" ] && download_file "${PROXYED_URL}" "${TAR_FILE}"; then
        DOWNLOAD_OK=1
    else
        echo -e "${Yellow}Direct download failed, attempting fallback download...${Font}"
        if download_file "${GITHUB_URL}" "${TAR_FILE}"; then
            DOWNLOAD_OK=1
        fi
    fi
fi

if [ "${DOWNLOAD_OK}" -ne 1 ]; then
    echo -e "${Red}Failed to download ${TAR_FILE}.${Font}"
    exit 1
fi

# extract
tar -xzf "${TAR_FILE}"
if [ ! -d "${FRP_FILE_NAME}" ]; then
    echo -e "${Red}Extraction failed or expected directory ${FRP_FILE_NAME} not found.${Font}"
    rm -f "${TAR_FILE}"
    exit 1
fi

# prepare target dir
${SUDO} mkdir -p "${FRP_PATH}"
# move binary
if [ -f "${FRP_FILE_NAME}/${FRP_NAME}" ]; then
    ${SUDO} mv -f "${FRP_FILE_NAME}/${FRP_NAME}" "${FRP_PATH}/"
    ${SUDO} chmod +x "${FRP_PATH}/${FRP_NAME}"
else
    echo -e "${Red}Expected binary ${FRP_FILE_NAME}/${FRP_NAME} not found in archive.${Font}"
    rm -rf "${FRP_FILE_NAME}" "${TAR_FILE}"
    exit 1
fi

# configure frpc.toml if not present
if [ ! -f "${FRP_PATH}/${FRP_NAME}.toml" ]; then
    RADOM_NAME=$(head -c 32 /dev/urandom | md5sum | head -c 8 || echo "rndname")

    cat > /tmp/${FRP_NAME}.toml <<EOF
serverAddr = "frp.freefrp.net"
serverPort = 7000
auth.method = "token"
auth.token = "freefrp.net"

[[proxies]]
name = "ssh_${RADOM_NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 7022
EOF

    ${SUDO} mv /tmp/${FRP_NAME}.toml "${FRP_PATH}/${FRP_NAME}.toml"
    ${SUDO} chmod 644 "${FRP_PATH}/${FRP_NAME}.toml"
fi

# configure systemd unit
if [ ! -f "${SYSTEMD_PATH}/${FRP_NAME}.service" ]; then
    cat > /tmp/${FRP_NAME}.service <<EOF
[Unit]
Description=Frp Server Service
After=network.target syslog.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=${FRP_PATH}/${FRP_NAME} -c ${FRP_PATH}/${FRP_NAME}.toml

[Install]
WantedBy=multi-user.target
EOF

    ${SUDO} mv -f /tmp/${FRP_NAME}.service "${SYSTEMD_PATH}/${FRP_NAME}.service"
    ${SUDO} chmod 644 "${SYSTEMD_PATH}/${FRP_NAME}.service"

    # finish install
    ${SUDO} systemctl daemon-reload
    ${SUDO} systemctl enable --now "${FRP_NAME}"
fi

# clean
rm -rf "${FRP_FILE_NAME}"
#rm -f "${TAR_FILE}"

echo -e "${Green}====================================================================${Font}"
echo -e "${Green}安装成功,请先修改 ${FRP_NAME}.toml 文件,确保格式及配置正确无误!${Font}"
echo -e "${Green}vi ${FRP_PATH}/${FRP_NAME}.toml${Font}"
echo -e "${Green}修改完毕后执行以下命令重启服务:${Font}"
echo -e "${Green}${SUDO} systemctl restart ${FRP_NAME}${Font}"
echo -e "${Green}====================================================================${Font}"
