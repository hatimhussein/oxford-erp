import './index.css'

import { getLayoutDirection } from '@/utils/direction'
import { loadTranslations } from '@/utils/translation'
import { createApp } from 'vue'
import router from './router'
import App from './App.vue'
import { createPinia } from 'pinia'
// import '../polyfills'

import {
  Button,
  Card,
  Input,
  setConfig,
  frappeRequest,
  resourcesPlugin,
} from 'frappe-ui'

// create a pinia instance
let pinia = createPinia()

let app = createApp(App)

document.documentElement.dir = getLayoutDirection()
document.documentElement.lang =
  window.education_portal?.lang || document.documentElement.lang || 'en'

setConfig('resourceFetcher', frappeRequest)

app.use(pinia)
app.use(router)
app.use(resourcesPlugin)

app.component('Button', Button)
app.component('Card', Card)
app.component('Input', Input)

router.isReady().then(async () => {
  await loadTranslations()
  app.mount('#app')
})
