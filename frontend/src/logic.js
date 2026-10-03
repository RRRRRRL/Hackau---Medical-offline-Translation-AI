export function apiErrorMessage(data, fallback = 'Processing failed. Please try again.') {
  const detail = data?.detail
  if (typeof detail === 'string') {
    if (/no speech recognized/i.test(detail)) return 'Speech unclear. Please ask the patient to repeat.'
    return detail
  }
  if (Array.isArray(detail)) return detail.map((item) => item.msg).filter(Boolean).join('; ') || fallback
  return fallback
}

export function criticalItems(keyInformation) {
  if (!keyInformation || typeof keyInformation !== 'object' || Array.isArray(keyInformation)) return []
  return Object.entries(keyInformation).flatMap(([key, value]) => {
    const values = Array.isArray(value) ? value : [value]
    return values
      .filter((item) => typeof item === 'string' || typeof item === 'number')
      .map((item) => ({ label: key.replaceAll('_', ' '), value: String(item) }))
      .filter((item) => item.value.trim())
  })
}

export function newStatement(result, language) {
  return {
    id: crypto.randomUUID(),
    kind: 'statement',
    language,
    text: result.original_text.trim(),
    details: criticalItems(result.key_information),
  }
}

export function newAnswer(question, answer, language) {
  return {
    id: crypto.randomUUID(),
    kind: 'answer',
    language,
    question: question[language],
    answer,
  }
}

export function statusLabel(value, mode) {
  if (mode === 'mock' || value === 'mock') return 'Demo'
  if (value === 'ready') return 'Ready'
  if (value === 'missing' || value === 'unavailable') return 'Unavailable'
  if (value === 'error') return 'Error'
  if (value === 'loading' || value == null) return 'Loading'
  return 'Unavailable'
}
