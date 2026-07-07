import frappe

frappe.init(site="development.localhost", sites_path="/home/frappe/frappe-bench/sites")
frappe.connect()

print("System Language:", frappe.db.get_single_value("System Settings", "language"))
users = frappe.db.sql("select name, language from tabUser where enabled=1", as_dict=1)
print("Users:", users)
print("Default lang list for RTL:", ["ar", "he", "fa", "ps"])
