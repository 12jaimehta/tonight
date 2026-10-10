import { describe, expect, it } from "vitest";

function letterWord(index: number): string {
  let n = index;
  let suffix = "";
  do {
    suffix = String.fromCharCode(97 + (n % 26)) + suffix;
    n = Math.floor(n / 26);
  } while (n > 0);
  return `item${suffix}`;
}
import { percentValue, scoreReading, tokenize } from "./score";

/** The matcher this change replaces. One later copy of an omitted word pulls the cursor forward. */
function legacyGreedyScore(expected: string, spoken: string) {
  const want = expected
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter(Boolean);
  const got = spoken
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter(Boolean);
  let cursor = 0;
  let correct = 0;
  for (const word of want) {
    let found = -1;
    for (let index = cursor; index < got.length; index += 1) {
      if (got[index] === word) {
        found = index;
        break;
      }
    }
    if (found !== -1) {
      correct += 1;
      cursor = found + 1;
    }
  }
  return { correct, total: want.length };
}

const passage =
  "She woke before sunrise, packed one small blue bag, then walked quietly past the old banyan toward the wide river with her younger brother Arun, counting wooden boats along warm stone steps while reading a short poem about fresh rain clouds above distant hills. She, Mina, smiled softly once more under calm evening stars tonight, happily.";

describe("scoreReading", () => {
  it("scores 55 of 56 when one she is left out", () => {
    const spoken = passage.replace(/^She\s+/, "");
    const before = legacyGreedyScore(passage, spoken);
    expect(before).toEqual({ correct: 12, total: 56 });

    const mark = scoreReading(passage, spoken);
    expect(tokenize(passage)).toHaveLength(56);
    expect(mark.total).toBe(56);
    expect(mark.correct).toBe(55);
    expect(mark.percent).toBe(98);
    expect(mark.missed).toEqual(["she"]);
    expect(mark.words.filter((word) => word.status === "missing")).toEqual([
      { expected: "she", spoken: null, status: "missing" },
    ]);
    expect(mark.extras).toEqual([]);
  });

  it("keeps later words when a word is inserted", () => {
    const mark = scoreReading("the cat sat", "the big cat sat");
    expect(mark.correct).toBe(3);
    expect(mark.total).toBe(3);
    expect(mark.percent).toBe(100);
    expect(mark.extras).toEqual(["big"]);
    expect(mark.words.map((word) => word.status)).toEqual(["correct", "extra", "correct", "correct"]);
  });

  it("marks a substitution without dropping the words around it", () => {
    const mark = scoreReading("the cat sat", "the dog sat");
    expect(mark.correct).toBe(2);
    expect(mark.total).toBe(3);
    expect(mark.missed).toEqual(["cat"]);
    expect(mark.extras).toEqual([]);
    expect(mark.words[1]).toEqual({ expected: "cat", spoken: "dog", status: "substituted" });
  });

  it("counts a repeated expected word only as often as it was spoken", () => {
    const mark = scoreReading("the the", "the");
    expect(mark.correct).toBe(1);
    expect(mark.total).toBe(2);
    expect(mark.words.filter((word) => word.status === "correct")).toHaveLength(1);
    expect(mark.missed).toEqual(["the"]);
  });

  it("treats a spoken repeat as an extra word", () => {
    const mark = scoreReading("the cat sat", "the cat cat sat");
    expect(mark.correct).toBe(3);
    expect(mark.total).toBe(3);
    expect(mark.extras).toEqual(["cat"]);
  });

  it("does not give a full mark for words said out of order", () => {
    const mark = scoreReading("alpha beta", "beta alpha");
    expect(mark.correct).toBe(1);
    expect(mark.correct).toBeLessThan(mark.total);
  });

  it("does not count a skipped opening as correct", () => {
    const mark = scoreReading("Birds fly south. The cat sat.", "the cat sat");
    expect(mark.correct).toBe(3);
    expect(mark.total).toBe(6);
    expect(mark.missed.slice(0, 3)).toEqual(["birds", "fly", "south"]);
    const matched = mark.words.filter((word) => word.status === "correct").map((word) => word.expected);
    expect(matched).not.toContain("birds");
  });

  it("matches numbers, contractions, and number words", () => {
    expect(tokenize("1,00,000")).toEqual(["100000"]);
    expect(tokenize("3.5")).toEqual(["3.5"]);
    expect(tokenize("3.50")).toEqual(["3.5"]);
    expect(tokenize("Don't")).toEqual(["dont"]);
    expect(tokenize("dont")).toEqual(["dont"]);
    expect(tokenize("Don’t")).toEqual(["dont"]);
    expect(scoreReading("Don't run", "dont run")).toMatchObject({ correct: 2, total: 2, percent: 100 });
    expect(scoreReading("It costs 3.5 rupees", "it costs 3.50 rupees")).toMatchObject({ correct: 4, total: 4 });
    expect(scoreReading("I saved 1,00,000", "i saved 100000")).toMatchObject({ correct: 3, total: 3 });
    expect(scoreReading("I have 7 pens", "i have seven pens")).toMatchObject({ correct: 4, total: 4, percent: 100 });
    expect(tokenize("twenty-five")).toEqual(["25"]);
    expect(scoreReading("Hello, world!", "hello world").correct).toBe(2);
  });

  it("keeps Devanagari vowel signs and nukta on the word", () => {
    expect(tokenize("किताब")).toEqual(["किताब"]);
    expect(tokenize("किताब")[0]).toContain("\u093F");
    expect(tokenize("पढ़ो")).toEqual(["पढ़ो"]);
    expect(tokenize("किताब पढ़ो")).toEqual(["किताब", "पढ़ो"]);
    const hindi = scoreReading("किताब पढ़ो", "किताब पढ़ो");
    expect(hindi.correct).toBe(2);
    expect(hindi.total).toBe(2);
    const half = scoreReading("किताब पढ़ो", "किताब");
    expect(half.correct).toBe(1);
    expect(half.total).toBe(2);
    expect(half.missed).toEqual(["पढ़ो"]);
  });

  it("folds case with Unicode default lowercase and compatibility characters", () => {
    expect(tokenize("I")).toEqual(["i"]);
    expect(tokenize("Σ")).toEqual(["σ"]);
    expect(tokenize("ﬁle")).toEqual(["file"]);
    expect(tokenize("４２")).toEqual(["42"]);
    expect(tokenize("४२")).toEqual(["42"]);
  });

  it("leaves fuzzy matching off unless asked", () => {
    const mark = scoreReading("plant", "plent");
    expect(mark.correct).toBe(0);
    expect(mark.words[0]?.status).toBe("substituted");
    const fuzzy = scoreReading("plant", "plent", { fuzzy: true });
    expect(fuzzy.correct).toBe(1);
  });

  it("does not divide by zero on an empty passage", () => {
    const mark = scoreReading("...", "hello");
    expect(mark.total).toBe(0);
    expect(mark.percent).toBeNull();
    expect(mark.correct).toBe(0);
    expect(mark.extras).toEqual(["hello"]);
  });

  it("rounds percents half up and never shows a false 100", () => {
    expect(percentValue(2, 3)).toBe(67);
    expect(percentValue(1, 8)).toBe(13);
    expect(percentValue(199, 200)).toBe(99);
    expect(percentValue(0, 0)).toBeNull();
    expect(percentValue(3, 3)).toBe(100);
    expect(scoreReading("a b c", "a b").percent).toBe(67);
  });

  it("tokenises to a stable form", () => {
    const samples = ["Don't run", "1,00,000", "किताब पढ़ो", "Hello, world!", "I have 7 pens", "3.5"];
    for (const sample of samples) {
      const once = tokenize(sample);
      expect(tokenize(once.join(" "))).toEqual(once);
    }
  });

  it("folds the same spellings as MarkingKit", () => {
    expect(tokenize("colour favourite metre litre maths")).toEqual(["color", "favorite", "meter", "liter", "math"]);
    expect(scoreReading("My favourite colour", "my favorite color")).toMatchObject({ correct: 3, total: 3 });
  });

  it("aligns 300 words quickly", () => {
    const words = Array.from({ length: 300 }, (_, index) => letterWord(index));
    const passageText = words.join(" ");
    const heard = words.filter((_, index) => index % 4 !== 0).join(" ");
    const start = performance.now();
    const mark = scoreReading(passageText, heard);
    const elapsed = performance.now() - start;
    expect(mark.total).toBe(300);
    expect(mark.correct).toBe(225);
    expect(elapsed).toBeLessThan(50);
  });
});
