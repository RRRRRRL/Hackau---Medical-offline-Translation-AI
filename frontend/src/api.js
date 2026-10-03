import { apiErrorMessage } from './logic.js'

export async function getHealth() {
  const response = await fetch('/health')
  if (!response.ok) throw new Error('Local service unavailable')
  return response.json()
}

export async function processAudio(blob, extension, source, target) {
  const form = new FormData()
  form.append('audio', blob, `recording.${extension}`)
  form.append('source_language', source)
  form.append('target_language', target)
  const response = await fetch('/process_audio', { method: 'POST', body: form })
  const data = await response.json().catch(() => null)
  if (!response.ok) throw new Error(apiErrorMessage(data))
  return data
}
