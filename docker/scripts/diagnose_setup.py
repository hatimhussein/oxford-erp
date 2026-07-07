import frappe
import json
import traceback

frappe.connect()

results = {
    "counts": {
        "Language": frappe.db.count("Language"),
        "Workspace": frappe.db.count("Workspace"),
        "Role": frappe.db.count("Role"),
        "User": frappe.db.count("User"),
        "Page": frappe.db.count("Page"),
    },
    "system_settings": {
        "setup_complete": frappe.db.get_single_value("System Settings", "setup_complete"),
        "language": frappe.db.get_single_value("System Settings", "language"),
    },
    "installed_apps": frappe.get_installed_apps(),
}

try:
    apps = frappe.get_all(
        "Installed Application",
        fields=["app_name", "has_setup_wizard", "is_setup_complete"],
    )
    results["installed_application"] = apps
except Exception as e:
    results["installed_application_error"] = str(e)

try:
    patches = frappe.get_all(
        "Patch Log",
        fields=["patch", "skipped"],
        order_by="creation desc",
        limit=10,
    )
    results["recent_patches"] = patches
except Exception as e:
    results["patch_log_error"] = str(e)

try:
    errors = frappe.get_all(
        "Error Log",
        fields=["creation", "method", "error"],
        order_by="creation desc",
        limit=5,
    )
    results["recent_errors"] = [
        {**e, "error": (e.get("error") or "")[:400]} for e in errors
    ]
except Exception as e:
    results["error_log_error"] = str(e)

try:
    from frappe.boot import get_bootinfo

    boot = get_bootinfo()
    results["bootinfo"] = {
        "setup_complete": boot.get("setup_complete"),
        "setup_wizard_requires": boot.get("setup_wizard_requires"),
        "setup_wizard_completed_apps": boot.get("setup_wizard_completed_apps"),
        "workspaces_pages_count": len(boot.get("workspaces", {}).get("pages", [])),
        "workspace_sidebar_item_count": len(boot.get("workspace_sidebar_item", {})),
        "user": boot.get("user", {}).get("name") if boot.get("user") else None,
        "lang": boot.get("lang"),
        "has_apps_data": bool(boot.get("apps_data")),
    }
except Exception:
    results["bootinfo_error"] = traceback.format_exc()

try:
    from frappe.desk.page.setup_wizard.setup_wizard import load_languages, load_user_details

    results["load_languages"] = load_languages()
    results["load_user_details"] = load_user_details()
except Exception:
    results["setup_wizard_api_error"] = traceback.format_exc()

try:
    from frappe.auth import LoginManager

    lm = LoginManager()
    lm.authenticate("Administrator", "admin")
    results["login"] = "OK"
except Exception:
    results["login_error"] = traceback.format_exc()

print(json.dumps(results, indent=2, default=str))
