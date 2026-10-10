import type { ReadingScore } from "./score";

export type Attempt = {
  id: string;
  at: string;
  transcript: string;
} & ReadingScore;

export type Homework = {
  id: string;
  instruction: string;
  passage: string;
  image: string;
  showMarksToChild: boolean;
  createdAt: string;
  attempts: Attempt[];
};

export type Remember = {
  id: string;
  homeworkId: string;
  word: string;
  createdAt: string;
};

export type Db = {
  homework: Homework[];
  remember: Remember[];
};
