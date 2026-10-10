/** @vitest-environment jsdom */

import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ChildSession } from "./ChildSession";

const saveAttempt = vi.fn(async (_id: string, transcript: string) => ({
  id: "attempt-1",
  at: "2026-10-10T00:00:00.000Z",
  transcript,
  correct: 5,
  total: 6,
  percent: 83,
  missed: ["mat"],
  extras: [] as string[],
  words: [
    { expected: "the", spoken: "the", status: "correct" as const },
    { expected: "cat", spoken: "cat", status: "correct" as const },
    { expected: "sat", spoken: "sat", status: "correct" as const },
    { expected: "on", spoken: "on", status: "correct" as const },
    { expected: "the", spoken: "the", status: "correct" as const },
    { expected: "mat", spoken: null, status: "missing" as const },
  ],
}));

vi.mock("@/lib/actions", () => ({
  saveAttempt: (id: string, transcript: string) => saveAttempt(id, transcript),
  rememberWords: vi.fn(async () => {}),
}));

type ResultEvent = {
  resultIndex: number;
  results: { length: number; [index: number]: { isFinal: boolean; 0: { transcript: string } } };
};

class FakeRecognition {
  static instances: FakeRecognition[] = [];
  lang = "";
  continuous = false;
  interimResults = false;
  onresult: ((event: ResultEvent) => void) | null = null;
  onend: (() => void) | null = null;

  start() {
    FakeRecognition.instances.push(this);
    this.onresult?.({ resultIndex: 0, results: { length: 0 } });
  }

  stop() {
    this.onend?.();
  }

  emit(transcript: string) {
    this.onresult?.({
      resultIndex: 0,
      results: { length: 1, 0: { isFinal: true, 0: { transcript } } },
    });
  }
}

class FakeUtterance {
  lang = "";
  rate = 1;
  constructor(public text: string) {}
}

const spoken: string[] = [];

beforeEach(() => {
  spoken.length = 0;
  FakeRecognition.instances = [];
  saveAttempt.mockClear();
  vi.stubGlobal("SpeechRecognition", FakeRecognition);
  vi.stubGlobal("webkitSpeechRecognition", FakeRecognition);
  vi.stubGlobal("SpeechSynthesisUtterance", FakeUtterance);
  vi.stubGlobal("speechSynthesis", {
    cancel() {},
    speak(utterance: FakeUtterance) {
      spoken.push(utterance.text);
      const active = FakeRecognition.instances.at(-1);
      active?.emit(utterance.text);
    },
  });
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderSession() {
  render(
    <ChildSession
      id="hw"
      instruction="Read the page"
      passage="The cat sat on the mat."
      image="page.png"
      showMarksToChild
    />,
  );
  return screen.getByRole("textbox");
}

describe("ChildSession playback", () => {
  it("keeps the transcript and score when the passage is played", async () => {
    const box = renderSession();
    fireEvent.change(box, { target: { value: "the cat sat on the" } });
    fireEvent.click(screen.getByRole("button", { name: "Mark this" }));
    expect(await screen.findByText("5 of 6")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Remember" })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Read it aloud" }));
    expect(box).toHaveProperty("value", "the cat sat on the");
    expect(screen.getByText("5 of 6")).toBeTruthy();

    act(() => {
      FakeRecognition.instances.at(-1)?.emit("the cat sat on the");
    });
    expect(box).toHaveProperty("value", "the cat sat on the");

    fireEvent.click(screen.getByRole("button", { name: "Hear the page" }));
    expect(spoken).toContain("The cat sat on the mat.");
    expect(box).toHaveProperty("value", "the cat sat on the");
    expect(screen.getByText("5 of 6")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: /^Hear$/ }));
    expect(spoken).toContain("mat");
    expect(box).toHaveProperty("value", "the cat sat on the");
    expect(screen.getByText("5 of 6")).toBeTruthy();
  });

  it("still records words the child says after playback", async () => {
    const box = renderSession();
    fireEvent.change(box, { target: { value: "typed first" } });
    fireEvent.click(screen.getByRole("button", { name: "Hear the page" }));
    expect(box).toHaveProperty("value", "typed first");

    fireEvent.click(screen.getByRole("button", { name: "Read it aloud" }));
    expect(box).toHaveProperty("value", "typed first");
    act(() => {
      FakeRecognition.instances.at(-1)?.emit("the cat sat");
    });
    expect(box).toHaveProperty("value", "the cat sat");
  });
});
