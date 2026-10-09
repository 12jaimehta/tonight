export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter(Boolean);
}

export function scoreReading(expected: string, spoken: string) {
  const want = tokenize(expected);
  const got = tokenize(spoken);
  const missed: string[] = [];
  let cursor = 0;
  let correct = 0;

  for (const word of want) {
    let found = -1;
    for (let i = cursor; i < got.length; i++) {
      if (got[i] === word) {
        found = i;
        break;
      }
    }
    if (found === -1) missed.push(word);
    else {
      correct += 1;
      cursor = found + 1;
    }
  }

  const uniqueMissed = [...new Set(missed)];
  const percent = want.length === 0 ? 0 : Math.round((correct / want.length) * 100);

  return { correct, total: want.length, percent, missed: uniqueMissed };
}
