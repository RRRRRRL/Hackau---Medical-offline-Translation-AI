import React, { useCallback, useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { getHealth, processAudio } from './api.js'
import { criticalItems, newAnswer, newStatement, statusLabel } from './logic.js'
import { languages, questions } from './phrases.js'
import './style.css'

const modes = [
  { id: 'quick', number: '01', title: 'Quick Questions', description: 'Ask what matters first', icon: 'questions' },
  { id: 'yesno', number: '02', title: 'Yes / No', description: 'For limited patient response', icon: 'yesno' },
  { id: 'conversation', number: '03', title: 'Free Conversation', description: 'Speak and translate', icon: 'mic' },
  { id: 'handoff', number: '04', title: 'Handoff', description: 'Patient-stated information', icon: 'handoff' },
]

function Icon({ name, size = 22 }) {
  const paths = {
    questions: <><path d="M4 5h16v11H9l-5 4V5Z"/><path d="M8 9h8M8 12h5"/></>,
    yesno: <><rect x="3" y="5" width="18" height="14" rx="3"/><path d="m7 12 2 2 3-4M15 10h3M15 14h3"/></>,
    mic: <><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M8 21h8"/></>,
    handoff: <><rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4.5h6M9 10h6M9 14h6M9 18h4"/></>,
    arrow: <path d="M5 12h14m-6-6 6 6-6 6"/>,
    back: <path d="M19 12H5m6 6-6-6 6-6"/>,
    play: <path d="m8 5 11 7-11 7V5Z"/>,
    check: <path d="m4 12 5 5L20 6"/>,
    refresh: <><path d="M20 11a8 8 0 1 1-2.5-5.8"/><path d="M20 3v5h-5"/></>,
    volume: <><path d="M4 9v6h4l5 4V5L8 9H4ZM17 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/></>,
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>
}

function ModelStatus({ health, error, online }) {
  const mode = health?.mode
  const items = [['Speech recognition', health?.components?.asr], ['Translation', health?.components?.translation], ['Speech output', health?.components?.tts]]
  return <section className="status-card" aria-label="System status">
    <div className="status-heading"><span className="eyebrow">SYSTEM STATUS</span><span className={`connection ${health?.ready && mode === 'local' ? 'ready' : ''}`}><span className="dot"/>{health?.ready && mode === 'local' ? 'Local models ready' : mode === 'mock' ? 'Demo mode' : error ? 'Service unavailable' : 'Checking service'}</span></div>
    <div className="status-grid">{items.map(([name, value]) => <div className="status-item" key={name}><span>{name}</span><strong className={value === 'ready' ? 'status-ready' : ''}>{error ? 'Unavailable' : statusLabel(value, mode)}</strong></div>)}<div className="status-item"><span>Offline</span><strong className={health?.ready && mode === 'local' && !online ? 'status-ready' : ''}>{!online && health?.ready && mode === 'local' ? 'Ready' : online ? 'Not verified' : 'Unavailable'}</strong></div></div>
    {mode === 'mock' && <p className="status-note">Demo responses and audio are simulated. No patient information is inferred from them.</p>}
    {error && <p className="status-note">Start the local FastAPI service to use speech translation.</p>}
  </section>
}

function LanguageSelector({ responder, patient, setResponder, setPatient, disabled, locked }) {
  function update(next, role) {
    if (role === 'responder') { setResponder(next); if (next === patient) setPatient(next === 'en' ? 'zh' : 'en') }
    else { setPatient(next); if (next === responder) setResponder(next === 'en' ? 'zh' : 'en') }
  }
  return <div className="language-card"><div className="language-head"><span className="eyebrow">COMMUNICATION PAIR</span><span className="local-label"><span className="dot"/>On this device</span></div><div className="language-row"><label><span>Responder language</span><select value={responder} disabled={disabled} onChange={(event) => update(event.target.value, 'responder')}>{Object.entries(languages).map(([code, name]) => <option key={code} value={code}>{name}</option>)}</select></label><span className="language-divider" aria-hidden="true">↔</span><label><span>Patient language</span><select value={patient} disabled={disabled} onChange={(event) => update(event.target.value, 'patient')}>{Object.entries(languages).map(([code, name]) => <option key={code} value={code}>{name}</option>)}</select></label></div><p className="helper">{locked ? 'Clear the handoff before changing languages. ' : ''}The current backend supports English and Chinese. Russian requires the teammate’s API and models.</p></div>
}

function SectionHeader({ number, title, description, onBack }) {
  return <div className="section-header"><button className="back-button" onClick={onBack}><Icon name="back" size={18}/> All modes</button><div className="section-title"><span className="section-number">{number}</span><div><h1>{title}</h1><p>{description}</p></div></div></div>
}

function App() {
  const [mode, setMode] = useState('home')
  const [responder, setResponder] = useState('en')
  const [patient, setPatient] = useState('zh')
  const [health, setHealth] = useState(null)
  const [healthError, setHealthError] = useState(false)
  const [online, setOnline] = useState(navigator.onLine)
  const [question, setQuestion] = useState(null)
  const [answer, setAnswer] = useState(null)
  const [speaker, setSpeaker] = useState('patient')
  const [recording, setRecording] = useState(false)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState(null)
  const [resultSource, setResultSource] = useState(null)
  const [error, setError] = useState('')
  const [audioError, setAudioError] = useState('')
  const [speaking, setSpeaking] = useState(false)
  const [handoff, setHandoff] = useState([])
  const [confirmClear, setConfirmClear] = useState(false)
  const recorder = useRef(null)
  const stream = useRef(null)
  const chunks = useRef([])
  const held = useRef(false)
  const player = useRef(null)

  const refreshHealth = useCallback(async () => {
    try { setHealth(await getHealth()); setHealthError(false) }
    catch { setHealth(null); setHealthError(true) }
  }, [])

  useEffect(() => {
    void refreshHealth()
    const timer = setInterval(refreshHealth, 30000)
    const updateOnline = () => setOnline(navigator.onLine)
    window.addEventListener('online', updateOnline)
    window.addEventListener('offline', updateOnline)
    return () => { clearInterval(timer); window.removeEventListener('online', updateOnline); window.removeEventListener('offline', updateOnline); stream.current?.getTracks().forEach((track) => track.stop()); window.speechSynthesis?.cancel() }
  }, [refreshHealth])

  function navigate(next) {
    if (recording || busy) return
    window.speechSynthesis?.cancel()
    setSpeaking(false); setError(''); setAudioError(''); setMode(next)
  }

  function speak(text, language) {
    setAudioError('')
    if (!window.speechSynthesis) { setAudioError('Local speech is unavailable. Show the patient the text.'); return }
    const voice = window.speechSynthesis.getVoices().find((item) => item.localService === true && item.lang.toLowerCase().startsWith(language === 'zh' ? 'zh' : 'en'))
    if (!voice) { setAudioError('No local voice is installed for this language. Show the patient the text.'); return }
    window.speechSynthesis.cancel()
    const utterance = new SpeechSynthesisUtterance(text)
    utterance.voice = voice; utterance.lang = voice.lang; utterance.rate = 0.88
    utterance.onstart = () => setSpeaking(true)
    utterance.onend = () => setSpeaking(false)
    utterance.onerror = () => { setSpeaking(false); setAudioError('Audio unavailable. The translated text remains visible.') }
    window.speechSynthesis.speak(utterance)
  }

  async function sendRecording(blob, extension, source, target) {
    if (!blob.size) { setError('Speech unclear. Please ask the patient to repeat.'); return }
    setBusy(true); setError(''); setResult(null)
    try {
      const data = await processAudio(blob, extension, source, target)
      setResult(data); setResultSource(source)
      if (!data.original_text?.trim() || !data.translation?.trim()) setError('Translation unavailable. Please record again.')
    } catch (err) { setError(err instanceof TypeError ? 'Local service unavailable. Check the backend connection.' : err.message); void refreshHealth() }
    finally { setBusy(false) }
  }

  async function startRecording() {
    if (busy || recording) return
    setError(''); setAudioError(''); setResult(null)
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) { setError('Microphone recording is unavailable in this browser.'); return }
    try {
      const media = await navigator.mediaDevices.getUserMedia({ audio: true })
      stream.current = media
      const formats = [['audio/webm;codecs=opus', 'webm'], ['audio/mp4', 'mp4'], ['audio/ogg;codecs=opus', 'ogg']]
      const chosen = formats.find(([mime]) => MediaRecorder.isTypeSupported(mime))
      const instance = chosen ? new MediaRecorder(media, { mimeType: chosen[0] }) : new MediaRecorder(media)
      const extension = chosen?.[1] || (instance.mimeType.includes('mp4') ? 'mp4' : 'webm')
      const source = speaker === 'patient' ? patient : responder
      const target = speaker === 'patient' ? responder : patient
      chunks.current = []
      instance.ondataavailable = (event) => { if (event.data.size) chunks.current.push(event.data) }
      instance.onerror = () => setError('Recording failed. Please try again.')
      instance.onstop = () => { media.getTracks().forEach((track) => track.stop()); stream.current = null; recorder.current = null; setRecording(false); void sendRecording(new Blob(chunks.current, { type: instance.mimeType }), extension, source, target) }
      recorder.current = instance; instance.start(); setRecording(true)
      if (!held.current) instance.stop()
    } catch (err) { stream.current?.getTracks().forEach((track) => track.stop()); stream.current = null; setError(err.name === 'NotAllowedError' ? 'Microphone permission denied. Allow access and try again.' : `Could not start recording: ${err.message}`) }
  }

  function releaseRecording() { held.current = false; if (recorder.current?.state === 'recording') recorder.current.stop() }
  function playResult() { setAudioError(''); player.current?.play().catch(() => setAudioError('Audio unavailable. The translated text remains visible.')) }

  const selected = questions.find((item) => item.id === question)
  const yesNoQuestions = questions.filter((item) => item.yesNo)
  const selectedYesNo = selected?.yesNo ? selected : yesNoQuestions[0]
  const extracted = criticalItems(result?.key_information)
  const active = modes.find((item) => item.id === mode)
  const canAddResult = result?.mode === 'local' && resultSource === patient && !!result.original_text?.trim() && !!result.translation?.trim() && !result.warning

  return <div className="app-shell">
    <header className="topbar"><button className="brand" onClick={() => navigate('home')} aria-label="FieldTalk home"><span className="brand-mark"><span/></span><span>FieldTalk</span></button><span className="topbar-label">OFFLINE EMERGENCY COMMUNICATION</span><button className="topbar-handoff" onClick={() => navigate('handoff')}>Handoff <span className="count">{handoff.length}</span></button></header>
    <main className="page">
      {mode === 'home' ? <>
        <div className="home-intro"><div><span className="eyebrow accent">FIELD COMMUNICATION SYSTEM</span><h1>Critical communication.<br/><span>Made clear.</span></h1><p>For a first responder and a responsive patient when every moment counts.</p></div><div className="hero-graphic" aria-hidden="true"><div className="graphic-ring ring-1"/><div className="graphic-ring ring-2"/><div className="graphic-center"><span className="brand-mark large"><span/></span></div><span className="graphic-label">LISTEN · UNDERSTAND · CONFIRM</span></div></div>
        <LanguageSelector responder={responder} patient={patient} setResponder={setResponder} setPatient={setPatient} disabled={recording || busy || handoff.length > 0} locked={handoff.length > 0}/>
        <div className="mode-heading"><div><span className="eyebrow">CHOOSE A WORKFLOW</span><h2>What do you need to do?</h2></div><p>One action at a time.</p></div>
        <div className="mode-grid">{modes.map((item) => <button key={item.id} className={`mode-card ${item.id === 'quick' ? 'primary-mode' : ''}`} onClick={() => navigate(item.id)}><span className="mode-top"><span className="mode-icon"><Icon name={item.icon} size={25}/></span><span className="mode-number">{item.number}</span></span><span className="mode-bottom"><strong>{item.title}</strong><small>{item.description}</small></span><span className="mode-arrow"><Icon name="arrow" size={20}/></span></button>)}</div>
        <ModelStatus health={health} error={healthError} online={online}/>
      </> : <>
        <SectionHeader number={active.number} title={active.title} description={active.description} onBack={() => navigate('home')}/>
        {mode === 'quick' && <div className="workflow-grid"><div className="question-list"><span className="eyebrow">SELECT A QUESTION</span>{questions.map((item) => <button key={item.id} className={`question-row ${question === item.id ? 'selected' : ''}`} onClick={() => { setQuestion(item.id); setAudioError(''); window.speechSynthesis?.cancel(); setSpeaking(false) }}><span className="question-category">{item.category}</span><strong>{item[responder]}</strong><Icon name="arrow" size={18}/></button>)}</div><div className="patient-panel">{selected ? <><span className="eyebrow">SHOW TO PATIENT · {languages[patient].toUpperCase()}</span><div className="patient-question">{selected[patient]}</div><p className="patient-translation">{selected[responder]}</p><button className="button button-primary button-wide" onClick={() => speak(selected[patient], patient)}><Icon name="volume"/> {speaking ? 'Playing locally…' : 'Play / Repeat question'}</button><p className="helper">Audio uses a local device voice when installed. Keep the text facing the patient.</p></> : <div className="empty-panel"><span className="empty-icon"><Icon name="questions" size={32}/></span><h2>Choose a question</h2><p>The patient-language phrase will appear here in large text.</p></div>}{audioError && <p className="inline-warning" role="alert">{audioError}</p>}</div></div>}
        {mode === 'yesno' && <div className="yesno-layout"><div className="question-select"><label htmlFor="yesno-question" className="eyebrow">ONE QUESTION AT A TIME</label><select id="yesno-question" value={selectedYesNo.id} onChange={(event) => { setQuestion(event.target.value); setAnswer(null); setAudioError('') }}>{yesNoQuestions.map((item) => <option key={item.id} value={item.id}>{item[responder]}</option>)}</select></div><div className="yesno-panel"><span className="eyebrow">PATIENT VIEW · {languages[patient].toUpperCase()}</span><h2>{selectedYesNo[patient]}</h2><p>{selectedYesNo[responder]}</p><button className="text-action" onClick={() => speak(selectedYesNo[patient], patient)}><Icon name="volume" size={20}/> {speaking ? 'Playing…' : 'Play question'}</button>{audioError && <p className="inline-warning" role="alert">{audioError}</p>}<div className="answer-grid"><button className={`answer-button yes ${answer === 'Yes' ? 'chosen' : ''}`} onClick={() => setAnswer('Yes')}><strong>{patient === 'zh' ? '是' : 'YES'}</strong><span>YES</span></button><button className={`answer-button no ${answer === 'No' ? 'chosen' : ''}`} onClick={() => setAnswer('No')}><strong>{patient === 'zh' ? '否' : 'NO'}</strong><span>NO</span></button></div></div>{answer && <div className="confirm-strip"><p>Patient selected <strong>{answer}</strong>. Confirm their choice before saving.</p><button className="button button-primary" onClick={() => { setHandoff((items) => [...items, newAnswer(selectedYesNo, answer, patient)]); setAnswer(null) }}><Icon name="check" size={18}/> Add to Handoff</button></div>}</div>}
        {mode === 'conversation' && <div className="conversation-layout"><div className="record-panel"><span className="eyebrow">WHO IS SPEAKING?</span><div className="segmented"><button className={speaker === 'patient' ? 'active' : ''} disabled={recording || busy} onClick={() => setSpeaker('patient')}>Patient <span>{languages[patient]}</span></button><button className={speaker === 'responder' ? 'active' : ''} disabled={recording || busy} onClick={() => setSpeaker('responder')}>Responder <span>{languages[responder]}</span></button></div><div className="direction">{speaker === 'patient' ? languages[patient] : languages[responder]} <Icon name="arrow" size={18}/> {speaker === 'patient' ? languages[responder] : languages[patient]}</div><button className={`record-button ${recording ? 'is-recording' : ''}`} disabled={busy} onPointerDown={(event) => { if (event.pointerType) { event.currentTarget.setPointerCapture(event.pointerId); held.current = true; void startRecording() } }} onPointerUp={releaseRecording} onPointerCancel={releaseRecording} onKeyDown={(event) => { if ((event.key === ' ' || event.key === 'Enter') && !event.repeat) { event.preventDefault(); held.current = true; void startRecording() } }} onKeyUp={(event) => { if (event.key === ' ' || event.key === 'Enter') { event.preventDefault(); releaseRecording() } }}><span className="record-icon"><Icon name="mic" size={34}/></span><strong>{recording ? 'Listening… release to send' : busy ? 'Processing audio…' : 'Hold to Speak'}</strong><small>{recording ? 'Keep holding while speaking' : busy ? 'Recognizing · translating · preparing speech' : 'Press and hold, then release'}</small></button><p className="record-hint">Speech is sent only to the local service on this device.</p></div><div className="result-panel"><span className="eyebrow">TRANSLATION RESULT</span>{busy && <div className="loading-state" role="status"><span className="spinner"/><h2>Processing audio</h2><p>Recognizing, translating, and preparing speech on the local service.</p></div>}{!busy && !result && !error && <div className="empty-panel"><span className="empty-icon"><Icon name="mic" size={32}/></span><h2>Ready to listen</h2><p>Hold the button and speak clearly. The original and translation will appear here.</p></div>}{error && <div className="error-panel" role="alert"><strong>{error.toLowerCase().includes('unclear') ? 'Speech unclear' : 'Communication interrupted'}</strong><p>{error}</p><button className="button button-outline" onClick={() => setError('')}>Try again</button></div>}{result && !busy && <><div className="result-block"><span className="eyebrow">ORIGINAL · {languages[resultSource]?.toUpperCase()}</span><p>{result.original_text || 'Speech unclear. Please ask the patient to repeat.'}</p></div><div className="result-block translated"><span className="eyebrow">TRANSLATION · {languages[resultSource === patient ? responder : patient]?.toUpperCase()}</span><p>{result.translation || 'Translation unavailable.'}</p></div>{result.warning && <p className="inline-warning" role="alert"><strong>Speech unclear.</strong> Please ask the patient to repeat. {result.warning}</p>}{extracted.length > 0 && <div className="critical-block"><span className="eyebrow">CRITICAL INFORMATION · UNCONFIRMED</span>{extracted.map((item, index) => <div key={`${item.label}-${index}`}><span>{item.label}</span><strong>{item.value}</strong></div>)}</div>}{result.audio_url && <audio ref={player} src={result.audio_url} preload="none" onError={() => setAudioError('Audio unavailable. The translated text remains visible.')}/>}<div className="result-actions"><button className="button button-outline" onClick={playResult} disabled={!result.audio_url}><Icon name="play" size={18}/> Play translation</button><button className="button button-outline" onClick={() => { setResult(null); setAudioError('') }}><Icon name="refresh" size={18}/> Record again</button></div>{audioError && <p className="inline-warning" role="alert">{audioError}</p>}{canAddResult ? <button className="button button-primary button-wide add-button" onClick={() => { setHandoff((items) => [...items, newStatement(result, patient)]); setResult(null) }}><Icon name="check" size={18}/> Add patient statement to Handoff</button> : <p className="helper">{result.mode === 'mock' ? 'Demo output cannot be added as patient-stated information.' : 'Only patient speech can be added to Handoff.'}</p>}</>}</div></div>}
        {mode === 'handoff' && <div className="handoff-layout"><div className="handoff-card"><div className="handoff-head"><span className="eyebrow">PATIENT-STATED INFORMATION</span><span className="handoff-badge"><Icon name="check" size={15}/> Explicitly added</span></div><h2>Emergency handoff</h2><p className="handoff-subtitle">Only information added by the responder appears here. This is not a diagnosis.</p><div className="handoff-meta"><span>Patient language</span><strong>{languages[patient]}</strong></div>{handoff.length ? <div className="handoff-entries">{handoff.map((item) => <div className="handoff-entry" key={item.id}><span className="entry-type">{item.kind === 'answer' ? 'PATIENT RESPONSE' : 'REPORTED STATEMENT'}</span>{item.kind === 'answer' ? <><p>{item.question}</p><strong>{item.answer}</strong></> : <><p>{item.text}</p>{item.details.length > 0 && <div className="entry-details">{item.details.map((detail, index) => <span key={index}>{detail.label}: {detail.value}</span>)}</div>}</>}</div>)}</div> : <div className="handoff-empty"><Icon name="handoff" size={28}/><h3>No information added yet</h3><p>Use Yes / No or add a real patient speech result to build this card.</p></div>}<div className="handoff-unknown"><span>Other details</span><strong>Unknown / Not stated</strong></div></div><div className="handoff-side"><div className="note-card"><span className="eyebrow">BEFORE HANDOFF</span><h3>Confirm with the patient.</h3><p>Recognition and translation may be uncertain. Review each statement before sharing it with the receiving team.</p></div>{handoff.length > 0 && (confirmClear ? <div className="clear-confirm"><p>Clear all {handoff.length} saved item{handoff.length === 1 ? '' : 's'} from this session?</p><div><button className="button button-danger" onClick={() => { setHandoff([]); setConfirmClear(false) }}>Clear session</button><button className="button button-outline" onClick={() => setConfirmClear(false)}>Cancel</button></div></div> : <button className="clear-button" onClick={() => setConfirmClear(true)}>Clear this session</button>)}</div></div>}
        <div className="workflow-status"><ModelStatus health={health} error={healthError} online={online}/></div>
      </>}
    </main>
    <footer className="site-footer"><span>FIELDTALK · FIELD COMMUNICATION SYSTEM</span><span>Translation aid for responsive patients. Confirm critical details.</span></footer>
  </div>
}

createRoot(document.getElementById('root')).render(<App />)
