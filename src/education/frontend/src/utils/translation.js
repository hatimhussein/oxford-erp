export function __(text) {
  return window.__translations?.[text] || text
}

export async function loadTranslations() {
  const lang =
    window.education_portal?.lang || document.documentElement.lang || 'en'

  if (!lang || lang === 'en') {
    window.__translations = {}
    return
  }

  try {
    const response = await fetch(
      `/api/method/frappe.translate.get_boot_translations?lang=${encodeURIComponent(lang)}`,
      {
        credentials: 'same-origin',
        headers: {
          Accept: 'application/json',
          'X-Frappe-CSRF-Token': window.csrf_token,
        },
      }
    )
    const data = await response.json()
    window.__translations = data.message || {}
  } catch {
    window.__translations = {}
  }
}
