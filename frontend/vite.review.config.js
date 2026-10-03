import { defineConfig, mergeConfig } from 'vite'
import { fileURLToPath } from 'node:url'
import baseline from './vite.config.js'

export default mergeConfig(baseline, defineConfig({
  server: { proxy: { '/api/review': 'http://127.0.0.1:8000' } },
  build: { rollupOptions: { input: {
    main: fileURLToPath(new URL('./index.html', import.meta.url)),
    review: fileURLToPath(new URL('./review.html', import.meta.url)),
  } } },
}))
