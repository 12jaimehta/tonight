import fs from "fs";
import path from "path";
import type { Attempt, Db, Homework, Remember } from "./types";

const dir = path.join(process.cwd(), "data");
const file = path.join(dir, "db.json");
const uploads = path.join(dir, "uploads");

function empty(): Db {
  return { homework: [], remember: [] };
}

function ensure() {
  fs.mkdirSync(uploads, { recursive: true });
  if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify(empty()));
}

export function readDb(): Db {
  ensure();
  const parsed = JSON.parse(fs.readFileSync(file, "utf8")) as Db;
  return {
    homework: parsed.homework ?? [],
    remember: parsed.remember ?? [],
  };
}

function writeDb(db: Db) {
  ensure();
  fs.writeFileSync(file, JSON.stringify(db, null, 2));
}

export function listHomework(): Homework[] {
  return readDb().homework.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}

export function getHomework(id: string): Homework | undefined {
  return readDb().homework.find((item) => item.id === id);
}

export function listRemember(): Remember[] {
  return readDb().remember.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
}

export function uploadPath(name: string) {
  return path.join(uploads, name);
}

export function addHomework(input: {
  instruction: string;
  passage: string;
  imageName: string;
  bytes: Buffer;
  showMarksToChild: boolean;
}): Homework {
  const id = crypto.randomUUID();
  const ext = path.extname(input.imageName).toLowerCase();
  const image = `${id}${ext}`;
  ensure();
  fs.writeFileSync(path.join(uploads, image), input.bytes);
  const homework: Homework = {
    id,
    instruction: input.instruction,
    passage: input.passage,
    image,
    showMarksToChild: input.showMarksToChild,
    createdAt: new Date().toISOString(),
    attempts: [],
  };
  const db = readDb();
  db.homework.push(homework);
  writeDb(db);
  return homework;
}

export function setShowMarks(id: string, show: boolean) {
  const db = readDb();
  const homework = db.homework.find((item) => item.id === id);
  if (!homework) return;
  homework.showMarksToChild = show;
  writeDb(db);
}

export function addAttempt(id: string, attempt: Attempt) {
  const db = readDb();
  const homework = db.homework.find((item) => item.id === id);
  if (!homework) return;
  homework.attempts.push(attempt);
  writeDb(db);
}

export function removeHomework(id: string) {
  const db = readDb();
  const homework = db.homework.find((item) => item.id === id);
  if (homework) {
    const imagePath = path.join(uploads, homework.image);
    if (fs.existsSync(imagePath)) fs.unlinkSync(imagePath);
  }
  db.homework = db.homework.filter((item) => item.id !== id);
  db.remember = db.remember.filter((item) => item.homeworkId !== id);
  writeDb(db);
}

export function addRemember(homeworkId: string, words: string[]) {
  const db = readDb();
  const known = new Set(
    db.remember.filter((item) => item.homeworkId === homeworkId).map((item) => item.word),
  );
  for (const word of words) {
    if (known.has(word)) continue;
    db.remember.push({
      id: crypto.randomUUID(),
      homeworkId,
      word,
      createdAt: new Date().toISOString(),
    });
  }
  writeDb(db);
}

export function removeRemember(id: string) {
  const db = readDb();
  db.remember = db.remember.filter((item) => item.id !== id);
  writeDb(db);
}
