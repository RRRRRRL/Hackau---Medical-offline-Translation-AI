import React, {useEffect, useRef, useState} from 'react';
import {AppState, Button, NativeModules, PermissionsAndroid, ScrollView, Text, TextInput, View} from 'react-native';
import {initWhisper} from 'whisper.rn';

const native = NativeModules.FieldTalk;
const languages = ['en', 'zh', 'ru'] as const;
type Language = typeof languages[number];

export default function App() {
  const [source, setSource] = useState<Language>('en');
  const [target, setTarget] = useState<Language>('zh');
  const [ready, setReady] = useState(false);
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('Prepare translation models online, then Load offline models.');
  const [original, setOriginal] = useState('');
  const [translated, setTranslated] = useState('');
  const [times, setTimes] = useState('');
  const context = useRef<Awaited<ReturnType<typeof initWhisper>> | null>(null);
  const cancelInference = useRef<(() => Promise<void>) | null>(null);
  const disposed = useRef(false);
  const fail = (e: unknown) => setStatus(e instanceof Error ? e.message : String(e));

  useEffect(() => {
    disposed.current = false;
    const listener = AppState.addEventListener('change', state => {
      if (state !== 'active') {
        native?.cancelRecording();
        native?.stopSpeech();
        void cancelInference.current?.();
        setRecording(false);
      }
    });
    return () => {
      disposed.current = true;
      listener.remove();
      native?.cancelRecording();
      native?.stopSpeech();
      void cancelInference.current?.();
      // Prototype: context is process-lived; do not release during active inference.
    };
  }, []);

  async function prepare() {
    setBusy(true);
    try {
      if (!native) throw new Error('FieldTalk native package is not registered.');
      await native.prepareTranslation();
      setStatus('Translation prepared. Install offline en-US, zh-CN and ru-RU TTS voices, then Load offline models.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }
  async function load() {
    setBusy(true); setReady(false);
    try {
      if (!native) throw new Error('FieldTalk native package is not registered.');
      await native.checkTranslation();
      for (const lang of languages) await native.checkVoice(lang);
      const path = await native.modelPath();
      if (!context.current) context.current = await initWhisper({filePath: path, useGpu: false});
      setReady(true); setStatus('Models available. Test a cold launch in airplane mode.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }
  async function start() {
    setBusy(true);
    try {
      const permission = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO);
      if (permission !== PermissionsAndroid.RESULTS.GRANTED) throw new Error('Microphone permission denied.');
      await native.stopSpeech();
      await native.startRecording();
      setOriginal(''); setTranslated(''); setTimes('');
      setRecording(true); setStatus('Recording. Keep turns under 30 seconds.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }
  async function finish() {
    setBusy(true); setRecording(false);
    let path: string | null = null;
    try {
      path = await native.stopRecording();
      const startTime = Date.now();
      const job = context.current!.transcribe(path!, {language: source});
      cancelInference.current = job.stop;
      const result = await job.promise;
      cancelInference.current = null;
      if (disposed.current) return;
      const text = result.result.trim();
      if (!text) throw new Error('No speech recognized. Please repeat.');
      setOriginal(text);
      setTimes(`ASR: ${Date.now() - startTime} ms`);
      setStatus('Review/edit the transcript, then translate.');
    } catch (e) { if (!disposed.current) fail(e); }
    finally {
      cancelInference.current = null;
      if (path) await native.deleteRecording(path).catch(() => {});
      if (!disposed.current) setBusy(false);
    }
  }
  async function translate() {
    setBusy(true); setTranslated('');
    try {
      const startTime = Date.now();
      const text = await native.translate(original, source, target);
      setTranslated(text);
      setTimes(previous => `${previous}; translation: ${Date.now() - startTime} ms`);
      setStatus('Confirm critical details before speaking.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }
  async function speak() {
    setBusy(true);
    try { await native.speak(translated, target); setStatus('Playback finished.'); }
    catch (e) { fail(e); } finally { setBusy(false); }
  }
  const locked = busy || recording;
  return <ScrollView contentContainerStyle={{padding: 24, gap: 12}}>
    <Text style={{fontSize: 28}}>FieldTalk Android</Text>
    <Text>Offline communication prototype, not a validated medical interpreter.</Text>
    <Button title="Prepare translation (internet required)" disabled={locked} onPress={prepare}/>
    <Button title="Load offline models" disabled={locked} onPress={load}/>
    <Text>Source: {source}; target: {target}</Text>
    <View style={{gap: 8}}>{languages.map(lang => <Button key={`s-${lang}`} title={`Source ${lang}`} disabled={locked}
      onPress={() => {setSource(lang); if (lang === target) setTarget(lang === 'en' ? 'zh' : 'en'); setOriginal(''); setTranslated('');}}/>)}</View>
    <View style={{gap: 8}}>{languages.map(lang => <Button key={`t-${lang}`} title={`Target ${lang}`} disabled={locked}
      onPress={() => {setTarget(lang); if (lang === source) setSource(lang === 'en' ? 'zh' : 'en'); setOriginal(''); setTranslated('');}}/>)}</View>
    <Button title="Start recording" disabled={!ready || locked} onPress={start}/>
    <Button title="Stop and recognize" disabled={!recording || busy} onPress={finish}/>
    <Text>{status}</Text>
    <TextInput multiline editable={!locked} value={original} onChangeText={text => {setOriginal(text); setTranslated('');}}
      placeholder="Review recognized text" style={{borderWidth: 1, padding: 12}}/>
    <Button title="Translate reviewed text" disabled={!ready || locked || !original.trim()} onPress={translate}/>
    <Text selectable>{translated}</Text>
    <Button title="Speak translation" disabled={!ready || locked || !translated.trim()} onPress={speak}/>
    <Button title="Stop playback" onPress={() => native?.stopSpeech()}/>
    <Text>{times}</Text>
    <Text>Confidence unavailable. No backend or laptop is used for inference. Recognition begins after recording stops.</Text>
  </ScrollView>;
}
