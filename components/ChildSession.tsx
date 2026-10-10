"use client";

import { useRef, useState } from "react";
import { rememberWords, saveAttempt } from "@/lib/actions";
import type { Attempt } from "@/lib/types";

type SpeechResult = {
  isFinal: boolean;
  0: { transcript: string };
};

type SpeechEvent = Event & {
  resultIndex: number;
  results: { length: number; [index: number]: SpeechResult };
};

type Listener = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((event: SpeechEvent) => void) | null;
  onend: (() => void) | null;
  start: () => void;
  stop: () => void;
};

export function ChildSession({
  id,
  instruction,
  passage,
  image,
  showMarksToChild,
}: {
  id: string;
  instruction: string;
  passage: string;
  image: string;
  showMarksToChild: boolean;
}) {
  const [listening, setListening] = useState(false);
  const [transcript, setTranscript] = useState("");
  const [attempt, setAttempt] = useState<Attempt | null>(null);
  const [saved, setSaved] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const listenerRef = useRef<Listener | null>(null);
  const listenGeneration = useRef(0);

  function haltRecognizer(invalidate: boolean) {
    if (invalidate) listenGeneration.current += 1;
    const active = listenerRef.current;
    listenerRef.current = null;
    try {
      active?.stop();
    } catch {
      // The recognizer throws if start() never succeeded.
    }
    setListening(false);
  }

  function speak(text: string) {
    // Chrome shares one speech engine between synthesis and recognition.
    // Starting playback aborts the recognizer, which then emits an empty
    // result or the passage it just heard. Drop that session so the child's
    // transcript and score stay put.
    haltRecognizer(true);
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "en-IN";
    utterance.rate = 0.9;
    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(utterance);
  }

  function hear() {
    speak(passage);
  }

  function readAloud() {
    const Recognition = (
      window as Window & {
        SpeechRecognition?: new () => Listener;
        webkitSpeechRecognition?: new () => Listener;
      }
    ).SpeechRecognition ??
      (window as Window & { webkitSpeechRecognition?: new () => Listener }).webkitSpeechRecognition;

    if (!Recognition) {
      setError("This browser has no microphone reader. Type the reading in the box below.");
      return;
    }

    haltRecognizer(true);
    const generation = ++listenGeneration.current;
    const listener = new Recognition();
    listener.lang = "en-IN";
    listener.continuous = true;
    listener.interimResults = true;
    listener.onresult = (event) => {
      if (generation !== listenGeneration.current) return;
      if (event.results.length === 0) return;
      let said = "";
      for (let i = 0; i < event.results.length; i++) said += event.results[i][0].transcript;
      if (!said.trim()) return;
      setTranscript(said);
    };
    listener.onend = () => {
      if (generation !== listenGeneration.current) return;
      setListening(false);
    };
    setListening(true);
    setError("");
    listenerRef.current = listener;
    listener.start();
  }

  function stop() {
    haltRecognizer(false);
  }

  async function mark() {
    setBusy(true);
    setError("");
    try {
      const result = await saveAttempt(id, transcript);
      setAttempt(result);
    } catch {
      setError("The mark could not be saved.");
    } finally {
      setBusy(false);
    }
  }

  async function keep(word: string) {
    await rememberWords(id, [word]);
    setSaved((current) => [...current, word]);
  }

  return (
    <div className="space-y-5">
      <div>
        <p className="text-sm text-[#5c564c]">Today</p>
        <h1 className="font-[family-name:var(--font-display)] text-3xl leading-tight">{instruction}</h1>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`/file/${image}`} alt="Homework page" className="w-full rounded-3xl border border-[var(--line)]" />

      <div className="flex flex-wrap gap-3">
        <button type="button" onClick={hear} className="rounded-full bg-[var(--ink)] px-4 py-2 text-sm text-white">
          Hear the page
        </button>
        {listening ? (
          <button type="button" onClick={stop} className="rounded-full bg-[var(--miss)] px-4 py-2 text-sm text-white">
            Stop
          </button>
        ) : (
          <button
            type="button"
            onClick={readAloud}
            className="rounded-full bg-[var(--green)] px-4 py-2 text-sm text-white"
          >
            Read it aloud
          </button>
        )}
      </div>

      <label className="block space-y-2">
        <span className="text-sm text-[#5c564c]">
          {listening ? "Listening…" : "What was read. You can also type it."}
        </span>
        <textarea
          value={transcript}
          onChange={(event) => setTranscript(event.target.value)}
          rows={5}
          className="w-full rounded-2xl border border-[var(--line)] bg-white px-4 py-3 leading-6"
        />
      </label>

      {error && <p className="text-sm text-[var(--miss)]">{error}</p>}

      <button
        type="button"
        onClick={mark}
        disabled={busy || transcript.trim().length === 0}
        className="rounded-full bg-[var(--green)] px-5 py-3 text-white disabled:opacity-40"
      >
        {busy ? "Marking…" : "Mark this"}
      </button>

      {attempt && (
        <section className="space-y-4 rounded-3xl bg-[var(--green-soft)] p-5">
          {showMarksToChild ? (
            <p className="font-[family-name:var(--font-display)] text-3xl">
              {attempt.correct} of {attempt.total}
            </p>
          ) : (
            <p className="text-[15px] leading-6">Saved. Your parent can see the mark.</p>
          )}

          {showMarksToChild && attempt.words.length > 0 && (
            <p className="text-sm leading-6" aria-label="Word by word">
              {attempt.words.map((word, index) => {
                const label = word.status === "extra" ? word.spoken : word.expected;
                return (
                  <span
                    key={index}
                    title={word.status}
                    className={word.status === "correct" ? undefined : "text-[var(--miss)]"}
                  >
                    {label}{" "}
                  </span>
                );
              })}
            </p>
          )}

          {attempt.missed.length === 0 ? (
            <p className="text-sm">
              {attempt.extras.length === 0
                ? "Every word was there."
                : `Every passage word was there. Also heard: ${attempt.extras.join(", ")}.`}
            </p>
          ) : (
            <ul className="space-y-2">
              {attempt.missed.map((word, index) => (
                <li key={`${word}-${index}`} className="flex items-center justify-between gap-3 rounded-2xl bg-white px-3 py-2">
                  <span>{word}</span>
                  <span className="flex gap-2 text-sm">
                    <button type="button" onClick={() => speak(word)} className="text-[var(--green)]">
                      Hear
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setAttempt(null);
                        setTranscript("");
                      }}
                      className="text-[var(--ink)]"
                    >
                      Again
                    </button>
                    <button
                      type="button"
                      onClick={() => keep(word)}
                      disabled={saved.includes(word)}
                      className="text-[var(--miss)] disabled:opacity-40"
                    >
                      {saved.includes(word) ? "Kept" : "Remember"}
                    </button>
                  </span>
                </li>
              ))}
            </ul>
          )}
          {attempt.missed.length > 0 && attempt.extras.length > 0 && (
            <p className="text-sm">Also heard: {attempt.extras.join(", ")}</p>
          )}
        </section>
      )}
    </div>
  );
}
