/**
 * Reading score for the web prototype.
 *
 * This matches MarkingKit on ios-v1: `ReadingNormalizer` tokenises, then a
 * Needleman–Wunsch aligner scores expected words in order. Match cost 0,
 * substitution cost 2, insertion or omission cost 1. On a tie, prefer a real
 * match, then a substitution, then an omission, then an insertion. A one-for-one
 * misread therefore stays substituted: splitting it into a missing word plus an
 * extra word has the same cost, and MarkingKit's plant/plent case expects
 * substituted. Fuzzy edit-distance stays off unless asked.
 */

export type WordStatus = "correct" | "missing" | "substituted" | "extra";

export type ScoredWord = {
  expected: string | null;
  spoken: string | null;
  status: WordStatus;
};

export type ReadingScore = {
  correct: number;
  total: number;
  /** Whole-number percent. Null when nothing was expected. Never 100 unless every expected word matched. */
  percent: number | null;
  /** Missing and substituted expected words, in passage order. Duplicates are kept. */
  missed: string[];
  /** Spoken words that were not paired with an expected word. */
  extras: string[];
  words: ScoredWord[];
};

export type ScoreOptions = {
  /** Single-character edit distance for words of 5+ characters. Off by default. */
  fuzzy?: boolean;
};

const spellings: Record<string, string> = {
  colour: "color",
  favourite: "favorite",
  metre: "meter",
  litre: "liter",
  maths: "math",
};

const smallNumbers: Record<string, number> = {
  zero: 0,
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
  eight: 8,
  nine: 9,
  ten: 10,
  eleven: 11,
  twelve: 12,
  thirteen: 13,
  fourteen: 14,
  fifteen: 15,
  sixteen: 16,
  seventeen: 17,
  eighteen: 18,
  nineteen: 19,
  twenty: 20,
  thirty: 30,
  forty: 40,
  fifty: 50,
  sixty: 60,
  seventy: 70,
  eighty: 80,
  ninety: 90,
};

const multipliers: Record<string, number> = {
  hundred: 100,
  thousand: 1_000,
  lakh: 100_000,
  crore: 10_000_000,
};

const devanagariDigits: Record<string, string> = {
  "०": "0",
  "१": "1",
  "२": "2",
  "३": "3",
  "४": "4",
  "५": "5",
  "६": "6",
  "७": "7",
  "८": "8",
  "९": "9",
};

const fullwidthDigits: Record<string, string> = {
  "０": "0",
  "１": "1",
  "２": "2",
  "３": "3",
  "４": "4",
  "５": "5",
  "６": "6",
  "７": "7",
  "８": "8",
  "９": "9",
};

export function tokenize(text: string): string[] {
  const folded = text.normalize("NFKC").toLowerCase();
  const scalars = [...folded];
  const tokens: string[] = [];
  let word = "";
  let index = 0;

  const flushWord = () => {
    if (!word) return;
    tokens.push(canonicalizeWord(word));
    word = "";
  };

  while (index < scalars.length) {
    const scalar = scalars[index];
    if (isIgnorable(scalar)) {
      index += 1;
      continue;
    }
    if (isDigit(scalar)) {
      flushWord();
      const [token, next] = consumeNumber(scalars, index);
      tokens.push(token);
      index = next;
      continue;
    }
    if (isLetter(scalar) || isMark(scalar)) {
      word += scalar;
      index += 1;
      continue;
    }
    if (isApostrophe(scalar) && word) {
      word += scalar;
      index += 1;
      continue;
    }
    // ZWJ and ZWNJ stay inside a word so Hindi conjuncts are not split.
    if ((scalar === "\u200C" || scalar === "\u200D") && word) {
      word += scalar;
      index += 1;
      continue;
    }
    if (isHyphen(scalar) && word && index + 1 < scalars.length && isLetter(scalars[index + 1])) {
      word += scalar;
      index += 1;
      continue;
    }
    flushWord();
    index += 1;
  }
  flushWord();
  return tokens;
}

export function scoreReading(expected: string, spoken: string, options: ScoreOptions = {}): ReadingScore {
  const want = tokenize(expected);
  const got = tokenize(spoken);
  const aligned = align(want, got, options.fuzzy === true);
  const words = aligned.map(toPublicWord);
  const correct = words.filter((word) => word.status === "correct").length;
  const missed = words.flatMap((word) =>
    (word.status === "missing" || word.status === "substituted") && word.expected ? [word.expected] : [],
  );
  const extras = words.flatMap((word) => (word.status === "extra" && word.spoken ? [word.spoken] : []));
  return {
    correct,
    total: want.length,
    percent: percentValue(correct, want.length),
    missed,
    extras,
    words,
  };
}

export function percentValue(correct: number, total: number): number | null {
  if (total <= 0) return null;
  if (correct >= total) return 100;
  const rounded = Math.floor((2 * correct * 100 + total) / (2 * total));
  return rounded >= 100 ? 99 : rounded;
}

function canonicalizeWord(raw: string): string {
  const stripped = [...raw].filter((scalar) => !isApostrophe(scalar)).join("");
  const number = numberWordValue(stripped);
  if (number !== null) return number;
  return spellings[stripped] ?? stripped;
}

function numberWordValue(word: string): string | null {
  const spaced = [...word].map((scalar) => (isHyphen(scalar) ? " " : scalar)).join("");
  return parseNumberWords(spaced);
}

function parseNumberWords(text: string): string | null {
  const parts = text.split(" ").filter(Boolean);
  if (parts.length === 0) return null;
  const hasLexical = parts.some((part) => smallNumbers[part] !== undefined || multipliers[part] !== undefined);
  if (!hasLexical) return null;
  if (parts.length === 2 && /^\d+$/.test(parts[0]) && multipliers[parts[1]] !== undefined) {
    return String(Number(parts[0]) * multipliers[parts[1]]);
  }
  let total = 0;
  let current = 0;
  let saw = false;
  for (const part of parts) {
    if (smallNumbers[part] !== undefined) {
      current += smallNumbers[part];
      saw = true;
    } else if (multipliers[part] !== undefined) {
      if (current === 0) current = 1;
      total += current * multipliers[part];
      current = 0;
      saw = true;
    } else if (/^\d+$/.test(part)) {
      current += Number(part);
      saw = true;
    } else {
      return null;
    }
  }
  if (!saw) return null;
  return String(total + current);
}

function consumeNumber(scalars: string[], start: number): [string, number] {
  let index = start;
  let raw = "";
  while (index < scalars.length) {
    const scalar = scalars[index];
    if (isDigit(scalar) || scalar === "," || scalar === ".") {
      raw += scalar;
      index += 1;
    } else if (isIgnorable(scalar)) {
      index += 1;
    } else {
      break;
    }
  }
  const canonical = canonicalNumber(raw);
  if (canonical !== null) return [canonical, index];

  let digits = "";
  let consumed = start;
  while (consumed < scalars.length && (isDigit(scalars[consumed]) || isIgnorable(scalars[consumed]))) {
    if (isDigit(scalars[consumed])) digits += asciiDigit(scalars[consumed]);
    consumed += 1;
  }
  if (consumed === start) consumed += 1;
  return [digits ? plainIntegerDigits(digits) : raw, consumed];
}

function canonicalNumber(raw: string): string | null {
  const mapped = [...raw].map((scalar) => asciiDigit(scalar)).join("");
  const cleaned = [...mapped].filter((scalar) => !isIgnorable(scalar)).join("");
  if (cleaned.includes(".")) {
    const pieces = cleaned.split(".");
    if (pieces.length !== 2) return null;
    const whole = stripGrouping(pieces[0]);
    if (whole === null || (!whole && !pieces[1])) return null;
    const fraction = pieces[1];
    if (![...fraction].every((scalar) => isAsciiDigit(scalar))) return null;
    if (whole.includes(",")) return null;
    return plainDecimal(whole || "0", fraction);
  }
  const digits = stripGrouping(cleaned);
  if (digits === null) return null;
  return plainIntegerDigits(digits);
}

/** Indian lakh/crore grouping or Western groups of three. Anything else is rejected. */
function stripGrouping(body: string): string | null {
  const parts = body.split(",");
  if (!parts.every((part) => part.length > 0 && [...part].every((scalar) => isAsciiDigit(scalar)))) return null;
  if (parts.length === 1) return parts[0];
  const western = parts[0].length >= 1 && parts[0].length <= 3 && parts.slice(1).every((part) => part.length === 3);
  const first = parts[0];
  const last = parts[parts.length - 1];
  const middle = parts.slice(1, -1);
  const indian = last.length === 3 && first.length >= 1 && first.length <= 3 && middle.every((part) => part.length === 2);
  if (!western && !indian) return null;
  return parts.join("");
}

function plainIntegerDigits(digits: string): string {
  const trimmed = digits.replace(/^0+/, "");
  return trimmed || "0";
}

function plainDecimal(whole: string, fraction: string): string {
  let wholeDigits = plainIntegerDigits(whole);
  let frac = fraction;
  if (frac.length > 6) {
    const roundDigit = frac[6];
    frac = frac.slice(0, 6);
    if (roundDigit >= "5") {
      const combined = addOne(`${wholeDigits}${frac}`.replace(/^0+/, "") || "0");
      if (combined.length <= 6) {
        wholeDigits = "0";
        frac = combined.padStart(6, "0");
      } else {
        wholeDigits = combined.slice(0, -6).replace(/^0+/, "") || "0";
        frac = combined.slice(-6);
      }
    }
  }
  frac = frac.replace(/0+$/, "");
  if (!frac) return wholeDigits;
  return `${wholeDigits}.${frac}`;
}

function addOne(digits: string): string {
  const chars = digits.split("");
  let carry = 1;
  for (let index = chars.length - 1; index >= 0 && carry; index -= 1) {
    const sum = chars[index].charCodeAt(0) - 48 + carry;
    chars[index] = String(sum % 10);
    carry = Math.floor(sum / 10);
  }
  if (carry) chars.unshift("1");
  return chars.join("");
}

type Step = "none" | "match" | "substitute" | "omit" | "insert";

type Aligned = {
  expected: string | null;
  spoken: string | null;
  status: "matched" | "substituted" | "omitted" | "inserted";
};

function align(expected: string[], heard: string[], fuzzy: boolean): Aligned[] {
  const rows = expected.length;
  const columns = heard.length;
  const cost = Array.from({ length: rows + 1 }, () => Array<number>(columns + 1).fill(0));
  const step = Array.from({ length: rows + 1 }, () => Array<Step>(columns + 1).fill("none"));

  for (let row = 1; row <= rows; row += 1) {
    cost[row][0] = row;
    step[row][0] = "omit";
  }
  for (let column = 1; column <= columns; column += 1) {
    cost[0][column] = column;
    step[0][column] = "insert";
  }

  for (let row = 1; row <= rows; row += 1) {
    for (let column = 1; column <= columns; column += 1) {
      const same = tokensMatch(expected[row - 1], heard[column - 1], fuzzy);
      let best = {
        cost: cost[row - 1][column - 1] + (same ? 0 : 2),
        priority: same ? 0 : 1,
        step: (same ? "match" : "substitute") as Step,
      };
      const omit = { cost: cost[row - 1][column] + 1, priority: 2, step: "omit" as Step };
      const insert = { cost: cost[row][column - 1] + 1, priority: 3, step: "insert" as Step };
      if (isBetter(omit, best)) best = omit;
      if (isBetter(insert, best)) best = insert;
      cost[row][column] = best.cost;
      step[row][column] = best.step;
    }
  }

  let row = rows;
  let column = columns;
  const reversed: Aligned[] = [];
  while (row > 0 || column > 0) {
    const kind = step[row][column];
    if (kind === "match" || kind === "substitute") {
      reversed.push({
        expected: expected[row - 1],
        spoken: heard[column - 1],
        status: kind === "match" ? "matched" : "substituted",
      });
      row -= 1;
      column -= 1;
    } else if (kind === "omit") {
      reversed.push({ expected: expected[row - 1], spoken: null, status: "omitted" });
      row -= 1;
    } else if (kind === "insert") {
      reversed.push({ expected: null, spoken: heard[column - 1], status: "inserted" });
      column -= 1;
    } else {
      row = 0;
      column = 0;
    }
  }
  return reversed.reverse();
}

function isBetter(candidate: { cost: number; priority: number }, other: { cost: number; priority: number }): boolean {
  if (candidate.cost !== other.cost) return candidate.cost < other.cost;
  return candidate.priority < other.priority;
}

function tokensMatch(expected: string, heard: string, fuzzy: boolean): boolean {
  if (expected === heard) return true;
  if (!fuzzy || [...expected].length < 5 || [...heard].length < 5) return false;
  return editDistance(expected, heard) <= 1;
}

function editDistance(a: string, b: string): number {
  const left = [...a];
  const right = [...b];
  let previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let i = 0; i < left.length; i += 1) {
    const current = [i + 1];
    for (let j = 0; j < right.length; j += 1) {
      const cost = left[i] === right[j] ? 0 : 1;
      current.push(Math.min(current[j] + 1, previous[j + 1] + 1, previous[j] + cost));
    }
    previous = current;
  }
  return previous[right.length];
}

function toPublicWord(word: Aligned): ScoredWord {
  if (word.status === "matched") return { expected: word.expected, spoken: word.spoken, status: "correct" };
  if (word.status === "omitted") return { expected: word.expected, spoken: null, status: "missing" };
  if (word.status === "substituted") return { expected: word.expected, spoken: word.spoken, status: "substituted" };
  return { expected: null, spoken: word.spoken, status: "extra" };
}

function isLetter(scalar: string): boolean {
  return /^\p{L}$/u.test(scalar);
}

function isMark(scalar: string): boolean {
  return /^\p{M}$/u.test(scalar);
}

function isDigit(scalar: string): boolean {
  return decimalValue(scalar) !== null;
}

function isAsciiDigit(scalar: string): boolean {
  return scalar >= "0" && scalar <= "9";
}

function asciiDigit(scalar: string): string {
  const mapped = devanagariDigits[scalar] ?? fullwidthDigits[scalar];
  if (mapped) return mapped;
  const value = decimalValue(scalar);
  if (value !== null) return String(value);
  return scalar;
}

function decimalValue(scalar: string): number | null {
  if (!/^\p{Nd}$/u.test(scalar)) return null;
  const code = scalar.codePointAt(0);
  if (code === undefined) return null;
  let zero = code;
  while (zero > 0 && /^\p{Nd}$/u.test(String.fromCodePoint(zero - 1))) zero -= 1;
  const digit = code - zero;
  return digit >= 0 && digit <= 9 ? digit : null;
}

function isApostrophe(scalar: string): boolean {
  return scalar === "'" || scalar === "’" || scalar === "‘" || scalar === "ʼ";
}

function isHyphen(scalar: string): boolean {
  return scalar === "-" || scalar === "‐" || scalar === "‑";
}

function isIgnorable(scalar: string): boolean {
  return scalar === "\u200B" || scalar === "\uFEFF" || scalar === "\u00AD";
}
