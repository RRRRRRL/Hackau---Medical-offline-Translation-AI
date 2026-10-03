import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "./style.css";

const labels = {
  en: "English",
  zh: "Chinese",
  ru: "Russian",
};

function App() {
  const [source, setSource] = useState("en");
  const [target, setTarget] = useState("zh");
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [health, setHealth] = useState(null);
  const [error, setError] = useState("");
  const recorder = useRef(null);
  const stream = useRef(null);
  const chunks = useRef([]);
  const player = useRef(null);

  useEffect(() => {
    fetch("/health")
      .then(async (response) => {
        if (!response.ok) throw new Error("Backend unavailable");
        setHealth(await response.json());
      })
      .catch(() =>
        setError("Backend unavailable. Start the local FastAPI server."),
      );
    return () => stream.current?.getTracks().forEach((track) => track.stop());
  }, []);

  async function sendAudio(blob, extension) {
    if (blob.size === 0) {
      setError("No audio recorded. Please try again.");
      return;
    }
    setBusy(true);
    setError("");
    setResult(null);
    const form = new FormData();
    form.append("audio", blob, `recording.${extension}`);
    form.append("source_language", source);
    form.append("target_language", target);
    try {
      const response = await fetch("/process_audio", {
        method: "POST",
        body: form,
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.detail || "Processing failed.");
      setResult(data);
      setTimeout(() => player.current?.play().catch(() => {}), 0);
    } catch (err) {
      setError(
        err instanceof TypeError
          ? "Backend unavailable. Check the local server."
          : err.message,
      );
    } finally {
      setBusy(false);
    }
  }

  async function startRecording() {
    setError("");
    setResult(null);
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      setError(
        "This browser cannot record audio. Use a current browser on localhost.",
      );
      return;
    }
    try {
      const media = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.current = media;
      const formats = [
        ["audio/webm;codecs=opus", "webm"],
        ["audio/mp4", "mp4"],
        ["audio/ogg;codecs=opus", "ogg"],
      ];
      const chosen = formats.find(([mime]) =>
        MediaRecorder.isTypeSupported(mime),
      );
      const instance = chosen
        ? new MediaRecorder(media, { mimeType: chosen[0] })
        : new MediaRecorder(media);
      const extension =
        chosen?.[1] || (instance.mimeType.includes("mp4") ? "mp4" : "webm");
      chunks.current = [];
      instance.ondataavailable = (event) => {
        if (event.data.size) chunks.current.push(event.data);
      };
      instance.onerror = () => setError("Recording failed. Please try again.");
      instance.onstop = () => {
        media.getTracks().forEach((track) => track.stop());
        stream.current = null;
        setRecording(false);
        void sendAudio(
          new Blob(chunks.current, { type: instance.mimeType }),
          extension,
        );
      };
      recorder.current = instance;
      instance.start();
      setRecording(true);
    } catch (err) {
      stream.current?.getTracks().forEach((track) => track.stop());
      stream.current = null;
      setError(
        err.name === "NotAllowedError"
          ? "Microphone permission denied. Allow access and retry."
          : `Could not start recording: ${err.message}`,
      );
    }
  }

  function stopRecording() {
    if (recorder.current?.state === "recording") recorder.current.stop();
  }

  return (
    <main>
      <h1>FieldTalk</h1>
      <p className="subtitle">Local ambulance communication prototype</p>
      <p className="boundary">
        Translation aid for responsive patients. Confirm critical details with
        the patient.
      </p>
      <div className="selectors">
        <label>
          Source language
          <select
            value={source}
            disabled={recording || busy}
            onChange={(event) => {
              const next = event.target.value;
              setSource(next);
              if (next !== "en") {
                setTarget("en");
              } else if (target === "en") {
                setTarget("zh");
              }
            }}
          >
            {Object.entries(labels).map(([code, name]) => (
              <option key={code} value={code}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Target language
          <select
            value={target}
            disabled={recording || busy}
            onChange={(event) => {
              const next = event.target.value;
              setTarget(next);
              if (next !== "en") {
                setSource("en");
              } else if (source === "en") {
                setSource("zh");
              }
            }}
          >
            {Object.entries(labels).map(([code, name]) => (
              <option key={code} value={code}>
                {name}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="actions">
        <button disabled={recording || busy} onClick={startRecording}>
          Start recording
        </button>
        <button disabled={!recording} onClick={stopRecording}>
          Stop recording
        </button>
      </div>
      {recording && (
        <p role="status">
          Recording… speak clearly, then press Stop recording.
        </p>
      )}
      {busy && <p role="status">Processing on the local device…</p>}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {result && (
        <section aria-label="Translation result">
          <h2>Original</h2>
          <p>{result.original_text}</p>
          <h2>Translation</h2>
          <p>{result.translation}</p>
          <p>
            Confidence:{" "}
            {result.confidence == null
              ? "Unavailable"
              : `${Math.round(result.confidence * 100)}%`}
          </p>
          {result.warning && <p className="error">{result.warning}</p>}
          <audio ref={player} src={result.audio_url} controls preload="auto" />
          <p>Time: {result.timings_ms.total} ms</p>
        </section>
      )}
      <footer>
        {health?.mode === "mock"
          ? "MOCK DEMO — recognized text, translation, and audio are simulated"
          : health?.ready
            ? "LOCAL MODE READY — disconnect network to verify"
            : health
              ? `LOCAL MODE NOT READY — ${Object.entries(health.components)
                  .filter(([, value]) => value !== "ready")
                  .map(([name]) => name)
                  .join(", ")} missing`
              : "Checking local backend…"}
      </footer>
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
