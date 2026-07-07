const RTL_LANGUAGES = ['ar', 'he', 'fa', 'ps']

export function isRtl(lang = null) {
  const value =
    lang ||
    window.education_portal?.lang ||
    document.documentElement.lang ||
    'en'
  return RTL_LANGUAGES.includes(value)
}

export function getLayoutDirection(lang = null) {
  return isRtl(lang) ? 'rtl' : 'ltr'
}

export function getInlineEndPlacement(defaultPlacement = 'right') {
  return isRtl() ? 'left' : defaultPlacement
}
