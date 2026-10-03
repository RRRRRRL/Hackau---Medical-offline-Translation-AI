import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './review.css'

const languages = { en: 'English', zh: 'Mandarin Chinese', ru: 'Russian' }

function App() {
  const [source, setSource] = useState('en')
  const [target, setTarget] = useState('zh')
  const [raw, setRaw] = useState('')
  const [draft, setDraft] = useState('')
  const [proposal, setProposal] = useState(null)
  const [confirmed, setConfirmed] = useState(false)
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState('')
  const [recording, setRecording] = useState(false)
  const [error, setError] = useState('')
  const [health, setHealth] = useState(null)
  const [asrMs, setAsrMs] = useState(null)
  const [testText, setTestText] = useState('I am allergic to pencil in.')
  const recorder = useRef(null)
  const stream = useRef(null)
  const timer = useRef(null)
  const alive = useRef(true)
  const requests = useRef(new Set())
  const player = useRef(null)

  async function request(path, options = {}) {
    const controller = new AbortController()
    requests.current.add(controller)
    const timeout = setTimeout(() => controller.abort(), 45000)
    try {
      const response = await fetch('/api/review' + path, { ...options, signal: controller.signal })
      const data = await response.json().catch(() => null)
      if (!response.ok) {
        const detail = data?.detail
        throw new Error(typeof detail === 'string' ? detail : 'Request failed. Check backend logs.')
      }
      return data
    } catch (err) {
      if (err.name === 'AbortError') throw new Error('Request timed out or was cancelled. Your transcript is preserved.')
      throw err
    } finally { clearTimeout(timeout); requests.current.delete(controller) }
  }
  function jsonPost(path, body) {
    return request(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
  }
  async function task(label, fn) {
    setBusy(label); setError('')
    try { await fn() }
    catch (err) { if (alive.current) setError(err.message) }
    finally { if (alive.current) setBusy('') }
  }
  function reset() {
    player.current?.pause()
    setRaw(''); setDraft(''); setProposal(null); setConfirmed(false); setResult(null); setAsrMs(null)
  }
  async function refreshHealth() {
    try { const value = await request('/health'); if (alive.current) setHealth(value) }
    catch { if (alive.current) setHealth(null) }
  }
  useEffect(() => {
    alive.current = true
    void refreshHealth()
    return () => {
      alive.current = false
      clearTimeout(timer.current)
      requests.current.forEach(controller => controller.abort())
      if (recorder.current?.state === 'recording') recorder.current.stop()
      stream.current?.getTracks().forEach(track => track.stop())
    }
  }, [])

  async function recognize(blob, name, lang) {
    await task('Recognizing locally…', async () => {
      const form = new FormData()
      form.append('audio', blob, name)
      form.append('source_language', lang)
      const data = await request('/recognize', { method: 'POST', body: form })
      if (!alive.current) return
      setRaw(data.original_text); setDraft(data.original_text); setAsrMs(data.timings_ms.asr)
      setProposal(null); setConfirmed(false); setResult(null)
    })
  }
  async function start() {
    reset()
    await task('Preparing microphone—wait before speaking…', async () => {
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) throw new Error('Recording is unavailable in this browser.')
      const media = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (!alive.current) { media.getTracks().forEach(t => t.stop()); return }
      stream.current = media
      const formats = [['audio/webm;codecs=opus', 'webm'], ['audio/mp4', 'mp4'], ['audio/ogg;codecs=opus', 'ogg']]
      const chosen = formats.find(([mime]) => MediaRecorder.isTypeSupported(mime))
      let instance
      try { instance = chosen ? new MediaRecorder(media, { mimeType: chosen[0] }) : new MediaRecorder(media) }
      catch (err) { media.getTracks().forEach(t => t.stop()); stream.current = null; throw err }
      const extension = chosen?.[1] || (instance.mimeType.includes('mp4') ? 'mp4' : 'webm')
      const lang = source
      const chunks = []
      let failed = false
      instance.ondataavailable = event => { if (event.data.size) chunks.push(event.data) }
      instance.onerror = () => {
        failed = true
        clearTimeout(timer.current)
        media.getTracks().forEach(t => t.stop())
        if (alive.current) { setRecording(false); setError('Recording failed. Try again.') }
      }
      instance.onstop = () => {
        clearTimeout(timer.current)
        media.getTracks().forEach(t => t.stop())
        stream.current = null; recorder.current = null
        if (!alive.current) return
        setRecording(false)
        if (!failed) void recognize(new Blob(chunks, { type: instance.mimeType }), 'recording.' + extension, lang)
      }
      recorder.current = instance
      try { instance.start() }
      catch (err) { media.getTracks().forEach(t => t.stop()); recorder.current = null; stream.current = null; throw err }
      setRecording(true)
      timer.current = setTimeout(() => { if (instance.state === 'recording') instance.stop() }, 30000)
    })
  }
  function stop() { if (recorder.current?.state === 'recording') recorder.current.stop() }
  async function review() {
    setProposal(null); setConfirmed(false); setResult(null); player.current?.pause()
    await task('Requesting an unverified suggestion…', async () => {
      const data = await jsonPost('/suggest', { text: raw, source_language: source })
      if (alive.current) setProposal(data)
    })
  }
  async function translate() {
    player.current?.pause(); setResult(null)
    await task('Translating confirmed text and preparing speech…', async () => {
      const data = await jsonPost('/translate', { original_text: raw, confirmed_text: draft,
        source_language: source, target_language: target, confirmed: true })
      if (alive.current) setResult(data)
    })
  }
  const locked = !!busy || recording
  return <main className="review-page">
    <header><h1>FieldTalk: transcript review</h1><a href="/">Existing demo</a></header>
    <p className="notice">Experimental communication aid—not diagnosis or medical advice. Suggestions are not audio-verified. Confirm medications, numbers, units, and negation with the speaker.</p>
    <p>Backend: {health?.mode || 'unavailable'} · Local review model: {health?.review_model || 'unknown'} <button disabled={locked} onClick={refreshHealth}>Refresh status</button></p>
    <div className="pair">
      <label>Source<select value={source} disabled={locked} onChange={e => {
        const next = e.target.value; setSource(next); if (next === target) setTarget(next === 'en' ? 'zh' : 'en'); reset()
      }}>{Object.entries(languages).map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></label>
      <label>Target<select value={target} disabled={locked} onChange={e => {
        const next = e.target.value; setTarget(next); if (next === source) { setSource(next === 'en' ? 'zh' : 'en'); reset() }
        setConfirmed(false); setResult(null); player.current?.pause()
      }}>{Object.entries(languages).map(([code, label]) => <option key={code} value={code}>{label}</option>)}</select></label>
    </div>
    <section><h2>1. Recognize only</h2>
      <button disabled={locked} onClick={start}>Start recording</button>
      <button disabled={!recording} onClick={stop}>Stop and recognize</button>
      <p role="status">{recording ? 'Listening—speak now. Maximum 30 seconds.' : busy || 'Ready. Wait for Listening before speaking.'}</p>
      <label>Or upload a short recording<input type="file" accept=".wav,.webm,.ogg,.mp4,.m4a" disabled={locked} onChange={e => {
        const file = e.target.files?.[0]; e.target.value = ''; if (file) { reset(); void recognize(file, file.name, source) }
      }}/></label>
      <details><summary>Fictional text-only test (does not test ASR)</summary>
        <textarea maxLength={600} value={testText} disabled={locked} onChange={e => setTestText(e.target.value)}/>
        <button disabled={locked || !testText.trim()} onClick={() => { reset(); setRaw(testText.trim()); setDraft(testText.trim()) }}>Use fictional test text</button>
      </details>
    </section>
    {error && <p className="error" role="alert">{error}</p>}
    {raw && <>
      <section><h2>2. Review the raw transcript</h2><blockquote>{raw}</blockquote>
        {asrMs != null && <p>ASR: {asrMs} ms</p>}
        <button disabled={locked} onClick={review}>Ask local model for a suggestion</button>
        <p>Optional. You can edit or keep the raw text without the model.</p>
        {proposal && <div className="proposal"><h3>Unverified suggestion · {proposal.status}</h3><p>{proposal.suggested_text}</p>
          <p>{proposal.notice}</p><p>Review: {proposal.review_ms} ms</p>
          {proposal.needs_repeat && <p className="error">Ask the speaker to repeat. Do not use an inferred answer.</p>}
          {proposal.changes.map((change, i) => <p key={i}><del>{change.original || '(nothing)'}</del> → <ins>{change.suggested || '(nothing)'}</ins></p>)}
          <button disabled={locked || proposal.needs_repeat} onClick={() => { setDraft(proposal.suggested_text); setConfirmed(false); setResult(null) }}>Copy suggestion to editable text</button>
        </div>}
      </section>
      <section><h2>3. Confirm before translating</h2>
        <label>Text to translate<textarea value={draft} maxLength={600} disabled={locked} onChange={e => {
          setDraft(e.target.value); setConfirmed(false); setResult(null); player.current?.pause()
        }}/></label>
        <button disabled={locked} onClick={() => { setDraft(raw); setConfirmed(false); setResult(null); player.current?.pause() }}>Restore original</button>
        <label className="checkbox"><input type="checkbox" checked={confirmed} disabled={locked} onChange={e => setConfirmed(e.target.checked)}/>I have checked this text with the speaker, including critical details.</label>
        <button disabled={locked || !confirmed || !draft.trim()} onClick={translate}>Translate confirmed text and prepare speech</button>
      </section>
    </>}
    {result && <section><h2>4. Translation</h2><p>Confirmed source: {result.confirmed_text}</p><p className="translation">{result.translation}</p>
      <audio ref={player} src={result.audio_url} controls preload="none" onError={() => setError('Audio playback failed; translated text remains visible.')}/>
      <p>Translation: {result.timings_ms.translation} ms · TTS: {result.timings_ms.tts} ms</p>
      <p>Human review, recording, upload, and playback are not included in backend stage timings.</p>
    </section>}
    <aside><h2>Communication prompts</h2><p>Please repeat the unclear part.</p><p>Please spell the medication name.</p><p>Please confirm the number and unit.</p><p>These are communication prompts, not treatment advice. No medical advice model or reference library is included.</p></aside>
    <footer>No conversation is saved by this page. Existing synthesized WAV files remain on the backend disk until deleted; this is not an all-ephemeral system.</footer>
  </main>
}
createRoot(document.getElementById('root')).render(<App />)
