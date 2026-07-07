#!/usr/bin/env bash
set -eu
cd /home/frappe/frappe-bench

echo "=== DB RECORD COUNTS ==="
bench --site development.localhost mariadb <<'SQL'
SELECT 'Language' as tbl, COUNT(*) as cnt FROM tabLanguage
UNION ALL SELECT 'Workspace', COUNT(*) FROM tabWorkspace
UNION ALL SELECT 'Role', COUNT(*) FROM tabRole
UNION ALL SELECT 'Module Def', COUNT(*) FROM `tabModule Def`
UNION ALL SELECT 'Page', COUNT(*) FROM tabPage
UNION ALL SELECT 'User', COUNT(*) FROM tabUser;
SQL

echo "=== SYSTEM SETTINGS ==="
bench --site development.localhost mariadb <<'SQL'
SELECT field, value FROM `tabSingles` WHERE doctype='System Settings' AND field IN ('setup_complete', 'language', 'country');
SQL

echo "=== INSTALLED APPLICATIONS ==="
bench --site development.localhost mariadb <<'SQL'
SELECT name, app_name, has_setup_wizard, is_setup_complete FROM `tabInstalled Application`;
SQL

echo "=== PATCH LOG (last 20) ==="
bench --site development.localhost mariadb <<'SQL'
SELECT patch, skipped FROM `tabPatch Log` ORDER BY creation DESC LIMIT 20;
SQL

echo "=== ERROR LOG (recent) ==="
bench --site development.localhost mariadb <<'SQL'
SELECT creation, method, LEFT(error, 200) as error FROM `tabError Log` ORDER BY creation DESC LIMIT 10;
SQL

echo "=== SETUP WIZARD PAGE ==="
bench --site development.localhost mariadb <<'SQL'
SELECT name, module, standard FROM tabPage WHERE name='setup-wizard';
SQL
