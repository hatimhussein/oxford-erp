#!/usr/bin/env bash
# Install host reverse-proxy so https://arrdh.com/oxforderp reaches Docker nginx (:8088).
# Run as root on the server. Detects Apache (incl. DirectAdmin) or Nginx.
set -euo pipefail

DOMAIN="${DOMAIN:-arrdh.com}"
PROXY_PREFIX="${PROXY_PREFIX:-/oxforderp}"
UPSTREAM="${UPSTREAM:-http://127.0.0.1:8088}"
MARKER="oxforderp-docker-proxy"

need_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		echo "ERROR: run as root (needed to write web-server config)" >&2
		exit 1
	fi
}

check_upstream() {
	echo "==> Checking Docker nginx at ${UPSTREAM}${PROXY_PREFIX}/desk"
	if ! curl -sI --max-time 5 "${UPSTREAM}${PROXY_PREFIX}/desk" | head -1 | grep -qE 'HTTP/'; then
		echo "WARNING: upstream not responding yet. Is 'docker compose ps' healthy?" >&2
	else
		curl -sI --max-time 5 "${UPSTREAM}${PROXY_PREFIX}/desk" | head -5
	fi
}

apache_snippet() {
	cat <<EOF
# BEGIN ${MARKER}
<IfModule mod_proxy.c>
	ProxyPreserveHost On
	RequestHeader set X-Forwarded-Proto "https" env=HTTPS
	RequestHeader set X-Forwarded-Port "443" env=HTTPS
	ProxyPass        ${PROXY_PREFIX}/socket.io  ${UPSTREAM}${PROXY_PREFIX}/socket.io
	ProxyPassReverse ${PROXY_PREFIX}/socket.io  ${UPSTREAM}${PROXY_PREFIX}/socket.io
	ProxyPass        ${PROXY_PREFIX}/           ${UPSTREAM}${PROXY_PREFIX}/
	ProxyPassReverse ${PROXY_PREFIX}/           ${UPSTREAM}${PROXY_PREFIX}/
</IfModule>
# END ${MARKER}
EOF
}

nginx_snippet() {
	cat <<EOF
# BEGIN ${MARKER}
location ${PROXY_PREFIX}/socket.io {
	proxy_pass ${UPSTREAM};
	proxy_http_version 1.1;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection "upgrade";
	proxy_set_header Host \$host;
	proxy_set_header X-Forwarded-Proto https;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_read_timeout 120s;
}
location ${PROXY_PREFIX}/ {
	proxy_pass ${UPSTREAM};
	proxy_http_version 1.1;
	proxy_set_header Host \$host;
	proxy_set_header X-Forwarded-Proto https;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header Upgrade \$http_upgrade;
	proxy_set_header Connection "upgrade";
	client_max_body_size 50m;
	proxy_read_timeout 120s;
}
# END ${MARKER}
EOF
}

install_directadmin_apache() {
	local user_conf
	user_conf="$(find /usr/local/directadmin/data/users -path "*/domains/${DOMAIN}.conf" 2>/dev/null | head -1 || true)"
	local custom_dir="/usr/local/directadmin/data/users"
	local httpd_custom=""

	# DirectAdmin CUSTOM HTTPD CONFIG path (per-domain)
	if [[ -n "${user_conf}" ]]; then
		local user
		user="$(echo "${user_conf}" | sed -n 's|.*/users/\([^/]*\)/domains/.*|\1|p')"
		httpd_custom="/usr/local/directadmin/data/users/${user}/httpd.conf"
		mkdir -p "/usr/local/directadmin/data/users/${user}"
		# Prefer Custom HTTPD Config include used by DA:
		# /usr/local/directadmin/data/users/USER/domains/DOMAIN.cust_httpd
		local cust="/usr/local/directadmin/data/users/${user}/domains/${DOMAIN}.cust_httpd"
		echo "==> Writing DirectAdmin custom HTTPD: ${cust}"
		apache_snippet > "${cust}"
		if command -v da >/dev/null 2>&1; then
			echo "==> Rebuilding DirectAdmin httpd config"
			da build rewrite_confs || true
		elif [[ -x /usr/local/directadmin/custombuild/build ]]; then
			/usr/local/directadmin/custombuild/build rewrite_confs || true
		fi
		systemctl reload httpd 2>/dev/null || systemctl reload apache2 2>/dev/null || service httpd reload 2>/dev/null || true
		echo "==> Installed Apache proxy via DirectAdmin ${cust}"
		return 0
	fi
	return 1
}

install_apache_generic() {
	local conf="/etc/httpd/conf.d/${MARKER}.conf"
	if [[ ! -d /etc/httpd/conf.d && -d /etc/apache2/conf-available ]]; then
		conf="/etc/apache2/conf-available/${MARKER}.conf"
		apache_snippet > "${conf}"
		a2enmod proxy proxy_http proxy_wstunnel headers rewrite 2>/dev/null || true
		a2enconf "${MARKER}" 2>/dev/null || true
		systemctl reload apache2
		echo "==> Installed ${conf}"
		return 0
	fi
	if [[ -d /etc/httpd/conf.d ]]; then
		apache_snippet > "${conf}"
		systemctl reload httpd 2>/dev/null || service httpd reload
		echo "==> Installed ${conf}"
		echo "NOTE: If ProxyPass is global, ensure it applies to the ${DOMAIN} HTTPS vhost."
		return 0
	fi
	return 1
}

install_nginx_generic() {
	local conf="/etc/nginx/conf.d/${MARKER}.conf"
	if [[ ! -d /etc/nginx ]]; then
		return 1
	fi
	echo "==> Nginx detected. Writing snippet to ${conf}"
	echo "# Include these location blocks inside server { server_name ${DOMAIN}; listen 443 ssl; }" > "${conf}"
	nginx_snippet >> "${conf}"
	echo "WARNING: conf.d files are often server-level; if nginx -t fails, paste the location blocks into the ${DOMAIN} server block manually."
	if nginx -t 2>/dev/null; then
		systemctl reload nginx
		echo "==> nginx reloaded"
	else
		echo "nginx -t failed — paste locations from nginx/host-arrdh-oxforderp.conf into the SSL server block for ${DOMAIN}" >&2
		rm -f "${conf}"
		return 1
	fi
	return 0
}

install_litespeed_htaccess() {
	local docroot=""
	for candidate in \
		"/home/${DOMAIN}/public_html" \
		"/home/arrdh.com/public_html" \
		"/var/www/html" \
		"/usr/local/lsws/${DOMAIN}/html"; do
		if [[ -d "${candidate}" ]]; then
			docroot="${candidate}"
			break
		fi
	done
	if [[ -z "${docroot}" ]]; then
		return 1
	fi

	local htaccess="${docroot}/.htaccess"
	echo "==> LiteSpeed: updating ${htaccess}"
	touch "${htaccess}"
	# Remove previous marker block if present
	if grep -q "BEGIN ${MARKER}" "${htaccess}" 2>/dev/null; then
		sed -i "/# BEGIN ${MARKER}/,/# END ${MARKER}/d" "${htaccess}"
	fi
	local tmp
	tmp="$(mktemp)"
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	local snippet="${script_dir}/../nginx/public_html-oxforderp.htaccess-snippet"
	if [[ -f "${snippet}" ]]; then
		# Normalize marker name inside snippet copy
		sed "s/oxforderp-docker-proxy/${MARKER}/g" "${snippet}" > "${tmp}"
		echo "" >> "${tmp}"
	else
		cat > "${tmp}" <<EOF
# BEGIN ${MARKER}
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^oxforderp\$ /oxforderp/ [R=301,L]
RewriteRule ^oxforderp/(.*)\$ http://127.0.0.1:8088/oxforderp/\$1 [P,L]
RewriteRule ^assets/(frappe|erpnext|education)/(.*)\$ http://127.0.0.1:8088/assets/\$1/\$2 [P,L]
RewriteRule ^assets-rtl/(.*)\$ http://127.0.0.1:8088/assets-rtl/\$1 [P,L]
RewriteRule ^api/method/(.*)\$ http://127.0.0.1:8088/api/method/\$1 [P,L]
RewriteRule ^api/resource/(.*)\$ http://127.0.0.1:8088/api/resource/\$1 [P,L]
RewriteRule ^files/(.*)\$ http://127.0.0.1:8088/files/\$1 [P,L]
RewriteRule ^private/files/(.*)\$ http://127.0.0.1:8088/private/files/\$1 [P,L]
RewriteRule ^socket\\.io(.*)\$ http://127.0.0.1:8088/socket.io\$1 [P,L]
</IfModule>
# END ${MARKER}

EOF
	fi
	cat "${htaccess}" >> "${tmp}"
	mv "${tmp}" "${htaccess}"
	chown --reference="${docroot}" "${htaccess}" 2>/dev/null || true

	# Reload LiteSpeed if available
	if [[ -x /usr/local/lsws/bin/lswsctrl ]]; then
		/usr/local/lsws/bin/lswsctrl restart || true
	elif command -v systemctl >/dev/null 2>&1; then
		systemctl restart lsws 2>/dev/null || systemctl restart lshttpd 2>/dev/null || true
	fi
	echo "==> Installed LiteSpeed rewrite proxy in ${htaccess}"
	return 0
}

main() {
	need_root
	check_upstream

	echo "==> Detecting web server..."

	# LiteSpeed first (this server returned Server: LiteSpeed)
	if [[ -d /usr/local/lsws ]] || pgrep -a litespeed >/dev/null 2>&1 || pgrep -a lshttpd >/dev/null 2>&1; then
		echo "    LiteSpeed found"
		if install_litespeed_htaccess; then
			echo "==> Done. Test: curl -sI https://${DOMAIN}${PROXY_PREFIX}/desk"
			exit 0
		fi
	fi

	if [[ -d /usr/local/directadmin ]]; then
		echo "    DirectAdmin found"
		if install_directadmin_apache; then
			echo "==> Done. Test: curl -sI https://${DOMAIN}${PROXY_PREFIX}/desk"
			exit 0
		fi
	fi

	if command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1 || [[ -d /etc/httpd ]] || [[ -d /etc/apache2 ]]; then
		echo "    Apache found"
		a2enmod proxy proxy_http proxy_wstunnel headers 2>/dev/null || true
		if install_apache_generic; then
			echo "==> Done. Test: curl -sI https://${DOMAIN}${PROXY_PREFIX}/desk"
			exit 0
		fi
	fi

	if command -v nginx >/dev/null 2>&1 || [[ -d /etc/nginx ]]; then
		echo "    Nginx found"
		nginx_snippet
		echo ""
		echo "Paste the location blocks above into the HTTPS server block for ${DOMAIN}, then:"
		echo "  nginx -t && systemctl reload nginx"
		exit 0
	fi

	echo "ERROR: Could not auto-install. For LiteSpeed, prepend these lines to public_html/.htaccess:" >&2
	cat >&2 <<'EOF'
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule ^oxforderp$ /oxforderp/ [R=301,L]
RewriteRule ^oxforderp/(.*)$ http://127.0.0.1:8088/oxforderp/$1 [P,L]
</IfModule>
EOF
	exit 1
}

main "$@"
