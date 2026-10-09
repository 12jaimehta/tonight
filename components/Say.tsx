"use client";

export function Say({ text }: { text: string }) {
  return (
    <button
      type="button"
      className="text-sm text-[var(--green)]"
      onClick={() => {
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = "en-IN";
        utterance.rate = 0.85;
        window.speechSynthesis.cancel();
        window.speechSynthesis.speak(utterance);
      }}
    >
      Hear
    </button>
  );
}
