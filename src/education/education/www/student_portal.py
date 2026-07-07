import frappe
from frappe.utils.jinja_globals import is_rtl


def get_context(context):
	abbr = frappe.db.get_single_value(
		"Education Settings", "school_college_name_abbreviation"
	)
	logo = frappe.db.get_single_value("Education Settings", "school_college_logo")
	context.abbr = abbr or "Frappe Education"
	context.logo = logo or "/favicon.png"
	context.lang = frappe.local.lang
	context.layout_direction = "rtl" if is_rtl() else "ltr"
