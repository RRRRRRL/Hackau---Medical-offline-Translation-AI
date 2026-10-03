import test from 'node:test'
import assert from 'node:assert/strict'
import { getHealth, processAudio } from '../src/api.js'
import { apiErrorMessage, criticalItems, newAnswer, newStatement, statusLabel } from '../src/logic.js'
import { questions } from '../src/phrases.js'

test('quick questions have both backend-supported languages and yes/no choices are binary', () => {
  assert.equal(questions.length, 7)
  for (const question of questions) {
    assert.ok(question.en && question.zh)
    assert.equal(typeof question.yesNo, 'boolean')
  }
  assert.equal(questions.find((question) => question.id === 'pain').yesNo, false)
})

test('handoff captures only explicit patient data and preserves unknown extraction as empty', () => {
  assert.deepEqual(criticalItems({}), [])
  assert.deepEqual(criticalItems({ allergy: ['Penicillin'], symptom: 'Chest pain' }), [
    { label: 'allergy', value: 'Penicillin' },
    { label: 'symptom', value: 'Chest pain' },
  ])
  const statement = newStatement({ original_text: '  I have chest pain.  ', key_information: {} }, 'en')
  assert.equal(statement.text, 'I have chest pain.')
  assert.deepEqual(statement.details, [])
  assert.equal(newAnswer(questions[1], 'No', 'zh').answer, 'No')
})

test('API sends the existing multipart fields and accepts its exact response shape', async () => {
  const expected = { original_text: 'Hello', translation: '你好', confidence: null, key_information: {}, audio_url: '/audio/123.wav', warning: null, timings_ms: { total: 1 }, mode: 'mock' }
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url, options) => {
    assert.equal(url, '/process_audio')
    assert.equal(options.method, 'POST')
    assert.deepEqual([...options.body.keys()], ['audio', 'source_language', 'target_language'])
    assert.equal(options.body.get('source_language'), 'en')
    assert.equal(options.body.get('target_language'), 'zh')
    assert.equal(options.body.get('audio').name, 'recording.webm')
    return { ok: true, json: async () => expected }
  }
  try { assert.deepEqual(await processAudio(new Blob(['audio']), 'webm', 'en', 'zh'), expected) }
  finally { globalThis.fetch = originalFetch }
})

test('health and FastAPI validation errors are handled without invented status', async () => {
  const originalFetch = globalThis.fetch
  globalThis.fetch = async (url) => url === '/health'
    ? { ok: true, json: async () => ({ mode: 'mock', ready: true, components: { asr: 'mock', translation: 'mock', tts: 'mock' } }) }
    : { ok: false, json: async () => ({ detail: [{ msg: 'Unsupported language pair' }] }) }
  try {
    assert.equal((await getHealth()).mode, 'mock')
    await assert.rejects(processAudio(new Blob(['audio']), 'webm', 'en', 'zh'), /Unsupported language pair/)
  } finally { globalThis.fetch = originalFetch }
  assert.equal(apiErrorMessage({ detail: 'Translation unavailable' }), 'Translation unavailable')
  assert.equal(statusLabel('mock', 'mock'), 'Demo')
  assert.equal(statusLabel('missing', 'local'), 'Unavailable')
  assert.equal(statusLabel('error', 'local'), 'Error')
  assert.equal(statusLabel(null, 'local'), 'Loading')
})
