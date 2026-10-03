import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  AppState,
  Button,
  NativeEventEmitter,
  NativeModules,
  PermissionsAndroid,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import {initWhisper} from 'whisper.rn';
import {
  inferCancellationStatus,
  isPairReadyForSpeech,
  isPairReadyForTurn,
  isValidPair,
  Language,
  shouldDiscardStaleTranslation,
  supportedLanguages,
} from './src/workflow';

const languages = supportedLanguages;

type FieldTalkNative = {
  prepareTranslation: () => Promise<void>;
  checkTranslationPair: (source: Language, target: Language) => Promise<void>;
  checkVoice: (language: Language) => Promise<void>;
  modelPath: () => Promise<string>;
  startRecording: () => Promise<void>;
  stopRecording: () => Promise<string>;
  cancelRecording: () => void;
  translate: (text: string, source: Language, target: Language) => Promise<string>;
  speak: (text: string, language: Language) => Promise<void>;
  stopSpeech: () => Promise<void>;
  deleteRecording: (path: string) => Promise<void>;
};

type FieldTalkEvent = {
  type:
    | 'recording_auto_stopped'
    | 'recording_cancelled'
    | 'recording_error'
    | 'playback_stopped'
    | 'playback_error';
  message?: string;
};

type VoiceStatus = Record<Language, string | null>;

const native = NativeModules.FieldTalk as FieldTalkNative | undefined;

function nextDifferentLanguage(lang: Language): Language {
  return lang === 'en' ? 'zh' : 'en';
}

export default function App() {
  const [source, setSource] = useState<Language>('en');
  const [target, setTarget] = useState<Language>('zh');
  const [prepared, setPrepared] = useState(false);
  const [ready, setReady] = useState(false);
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const [status, setStatus] = useState('Run Prepare translation while online, then Load offline models.');
  const [original, setOriginal] = useState('');
  const [translated, setTranslated] = useState('');
  const [times, setTimes] = useState('');
  const [voiceStatus, setVoiceStatus] = useState<VoiceStatus>({en: null, zh: null, ru: null});
  const [pairError, setPairError] = useState<string | null>(null);

  const context = useRef<Awaited<ReturnType<typeof initWhisper>> | null>(null);
  const disposed = useRef(false);
  const inferenceTicket = useRef(0);
  const translateTicket = useRef(0);
  const originalRef = useRef('');
  const sourceRef = useRef<Language>('en');
  const targetRef = useRef<Language>('zh');

  const fail = useCallback((e: unknown) => {
    const message = e instanceof Error ? e.message : String(e);
    setStatus(message);
  }, []);

  const pairReadyForSpeech = useMemo(() => isPairReadyForSpeech(voiceStatus[target]), [target, voiceStatus]);

  const refreshReadiness = useCallback(async (nextSource: Language, nextTarget: Language) => {
    if (!native) {
      setPairError('FieldTalk native package is not registered.');
      setReady(false);
      return;
    }

    const nextVoiceStatus: VoiceStatus = {en: null, zh: null, ru: null};
    for (const lang of languages) {
      try {
        await native.checkVoice(lang);
      } catch (e) {
        nextVoiceStatus[lang] = e instanceof Error ? e.message : String(e);
      }
    }
    setVoiceStatus(nextVoiceStatus);

    try {
      await native.checkTranslationPair(nextSource, nextTarget);
      setPairError(null);
      setReady(true);
      setStatus(
        nextVoiceStatus[nextTarget]
          ? `${nextVoiceStatus[nextTarget]} Translation ready for ${nextSource}->${nextTarget}; choose another target for speech or install its voice offline.`
          : `Offline models ready for ${nextSource}->${nextTarget}.`,
      );
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      setPairError(message);
      setReady(false);
      setStatus(message);
    }
  }, []);

  useEffect(() => {
    originalRef.current = original;
  }, [original]);

  useEffect(() => {
    sourceRef.current = source;
  }, [source]);

  useEffect(() => {
    targetRef.current = target;
  }, [target]);

  useEffect(() => {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    const emitter = new NativeEventEmitter(NativeModules.FieldTalk);
    const subscription = emitter.addListener('FieldTalkEvent', event => {
      const payload = event as FieldTalkEvent;
      if (payload.type === 'recording_auto_stopped') {
        setRecording(false);
        setStatus(payload.message ?? 'Recording reached the cap and stopped.');
        finish().catch(() => {});
      } else if (payload.type === 'recording_cancelled') {
        setRecording(false);
        setBusy(false);
        setStatus(payload.message ?? 'Recording cancelled.');
      } else if (payload.type === 'recording_error') {
        setRecording(false);
        setBusy(false);
        setStatus(payload.message ?? 'Recording failed.');
      } else if (payload.type === 'playback_stopped') {
        setSpeaking(false);
        setStatus(payload.message ?? 'Playback stopped.');
      } else if (payload.type === 'playback_error') {
        setSpeaking(false);
        setStatus(payload.message ?? 'Playback failed.');
      }
    });

    const appStateSub = AppState.addEventListener('change', state => {
      if (state !== 'active') {
        native.cancelRecording();
        native.stopSpeech().catch(() => {});
      }
    });

    return () => {
      disposed.current = true;
      appStateSub.remove();
      subscription.remove();
      native.cancelRecording();
      native.stopSpeech().catch(() => {});
      if (context.current) {
        context.current.release().catch(() => {});
        context.current = null;
      }
    };
  }, []);

  useEffect(() => {
    setTranslated('');
    setTimes('');
    if (prepared) {
      refreshReadiness(source, target).catch(() => {});
    }
  }, [prepared, refreshReadiness, source, target]);

  async function prepare() {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    setBusy(true);
    try {
      await native.prepareTranslation();
      setPrepared(true);
      setStatus('Translation downloads completed. Install offline voices, then load models.');
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  async function load() {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    setBusy(true);
    try {
      const modelPath = await native.modelPath();
      if (!context.current) {
        context.current = await initWhisper({filePath: modelPath, useGpu: false});
      }
      await refreshReadiness(sourceRef.current, targetRef.current);
      setPrepared(true);
      setStatus(current => `${current} Cold-launch airplane-mode verification still required on device.`);
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  async function start() {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    if (!ready || pairError) {
      setStatus(pairError ?? 'Current pair is not ready.');
      return;
    }

    setBusy(true);
    try {
      const permission = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO);
      if (permission !== PermissionsAndroid.RESULTS.GRANTED) {
        throw new Error('Microphone permission denied.');
      }
      await native.stopSpeech();
      setSpeaking(false);
      await native.startRecording();
      setOriginal('');
      setTranslated('');
      setTimes('');
      inferenceTicket.current += 1;
      setRecording(true);
      setStatus('Recording... stop manually or wait for the 30 second cap.');
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  async function finish() {
    if (!native || !context.current) {
      setStatus('Whisper is not loaded yet.');
      return;
    }

    setBusy(true);
    setRecording(false);
    let path: string | null = null;
    const localTicket = inferenceTicket.current;

    try {
      path = await native.stopRecording();
      const startAt = Date.now();
      const {promise} = context.current.transcribe(path, {language: sourceRef.current});
      const result = await promise;

      if (disposed.current || localTicket !== inferenceTicket.current) {
        return;
      }

      const text = result.result.trim();
      if (!text) {
        throw new Error('No speech recognized.');
      }

      setOriginal(text);
      setTranslated('');
      setTimes(`ASR ${Date.now() - startAt}ms`);
      setStatus('Review transcript, then translate.');
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      setStatus(inferCancellationStatus(message));
    } finally {
      if (path) {
        await native.deleteRecording(path).catch(() => {});
      }
      setBusy(false);
    }
  }

  async function translate() {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    const currentText = original.trim();
    if (!currentText) {
      setStatus('Transcript is empty.');
      return;
    }

    if (!isValidPair(source, target)) {
      setStatus('Source and target must differ.');
      return;
    }

    setBusy(true);
    setTranslated('');
    const localTicket = ++translateTicket.current;
    const startAt = Date.now();

    try {
      const text = await native.translate(currentText, source, target);
      if (
        shouldDiscardStaleTranslation({
          requestTicket: localTicket,
          currentTicket: translateTicket.current,
          requestedText: currentText,
          currentText: originalRef.current.trim(),
          requestedSource: source,
          currentSource: sourceRef.current,
          requestedTarget: target,
          currentTarget: targetRef.current,
        })
      ) {
        setStatus('Discarded stale translation result after transcript/language change. Re-run Translate.');
        return;
      }
      setTranslated(text);
      setTimes(previous => `${previous ? `${previous}; ` : ''}translate ${Date.now() - startAt}ms`);
      setStatus('Confirm critical details before playback.');
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  }

  async function speak() {
    if (!native) {
      setStatus('FieldTalk native package is not registered.');
      return;
    }

    if (voiceStatus[target]) {
      setStatus(voiceStatus[target] as string);
      return;
    }

    if (!translated.trim()) {
      setStatus('Nothing to speak.');
      return;
    }

    setBusy(true);
    setSpeaking(true);
    try {
      await native.speak(translated, target);
      setStatus('Playback finished.');
    } catch (e) {
      fail(e);
    } finally {
      setSpeaking(false);
      setBusy(false);
    }
  }

  const locked = busy || recording || speaking;
  const canStartTurn = isPairReadyForTurn({
    ready,
    busy: locked,
    recording,
    pairError,
  });

  return (
    <ScrollView contentContainerStyle={{padding: 20, gap: 10}}>
      <Text style={{fontSize: 24, fontWeight: '700'}}>FieldTalk Android Offline Prototype</Text>
      <Text>Offline support: English, Mandarin Chinese and Russian. Not a diagnosis tool.</Text>
      <Button title="Prepare translation (online only)" disabled={locked} onPress={prepare} />
      <Button title="Load offline models" disabled={locked} onPress={load} />
      <Text testID="pair">Pair: {source} {'->'} {target}</Text>
      <Text testID="status">{status}</Text>
      <Text>Voice status EN: {voiceStatus.en ?? 'ready'}</Text>
      <Text>Voice status ZH: {voiceStatus.zh ?? 'ready'}</Text>
      <Text>Voice status RU: {voiceStatus.ru ?? 'ready'}</Text>

      <View style={{gap: 6}}>
        {languages.map(lang => (
          <Button
            key={`src-${lang}`}
            title={`Source ${lang}`}
            disabled={locked}
            onPress={() => {
              setSource(lang);
              if (lang === target) {
                setTarget(nextDifferentLanguage(lang));
              }
              setOriginal('');
              setTranslated('');
            }}
          />
        ))}
      </View>

      <View style={{gap: 6}}>
        {languages.map(lang => (
          <Button
            key={`tgt-${lang}`}
            title={`Target ${lang}`}
            disabled={locked}
            onPress={() => {
              setTarget(lang);
              if (lang === source) {
                setSource(nextDifferentLanguage(lang));
              }
              setOriginal('');
              setTranslated('');
            }}
          />
        ))}
      </View>

      <Button title="Start recording" disabled={!canStartTurn} onPress={start} />
      <Button title="Stop and recognize" disabled={!recording || busy} onPress={finish} />

      <TextInput
        multiline
        editable={!locked}
        value={original}
        onChangeText={text => {
          setOriginal(text);
          setTranslated('');
          translateTicket.current += 1;
        }}
        placeholder="Editable transcript"
        style={{borderWidth: 1, borderColor: '#777', borderRadius: 6, padding: 8, minHeight: 90}}
      />

      <Button title="Translate reviewed text" disabled={!ready || locked || !original.trim()} onPress={translate} />
      <Text selectable testID="translation">{translated}</Text>
      <Button title="Speak translation" disabled={!ready || locked || !translated.trim() || !pairReadyForSpeech} onPress={speak} />
      <Button
        title="Stop playback"
        disabled={locked && !speaking}
        onPress={() => {
          native?.stopSpeech().catch(() => {});
        }}
      />
      <Text testID="timings">{times}</Text>
      <Text>Inference is local-only on Android device. No server/laptop fallback.</Text>
    </ScrollView>
  );
}
