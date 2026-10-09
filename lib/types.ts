export type Attempt = {
  id: string;
  at: string;
  transcript: string;
  correct: number;
  total: number;
  percent: number;
  missed: string[];
};

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
