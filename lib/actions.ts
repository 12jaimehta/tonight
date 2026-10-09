"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { scoreReading } from "./score";
import {
  addAttempt,
  addHomework,
  addRemember,
  removeHomework,
  removeRemember,
  setShowMarks,
} from "./store";

const imageTypes = new Set([".jpg", ".jpeg", ".png", ".webp", ".gif"]);

export async function createHomework(formData: FormData) {
  const instruction = String(formData.get("instruction") || "").trim();
  const passage = String(formData.get("passage") || "").trim();
  const showMarksToChild = formData.get("showMarks") === "on";
  const image = formData.get("image");

  if (!instruction || !passage || !(image instanceof File) || image.size === 0) {
    redirect("/new?error=missing");
  }

  const ext = image.name.includes(".") ? image.name.slice(image.name.lastIndexOf(".")).toLowerCase() : "";
  if (!imageTypes.has(ext)) redirect("/new?error=image");

  const bytes = Buffer.from(await image.arrayBuffer());
  addHomework({ instruction, passage, imageName: image.name, bytes, showMarksToChild });
  revalidatePath("/");
  redirect("/");
}

export async function toggleMarks(formData: FormData) {
  const id = String(formData.get("id") || "");
  setShowMarks(id, formData.get("showMarks") === "on");
  revalidatePath("/");
  revalidatePath(`/h/${id}`);
}

export async function deleteHomework(formData: FormData) {
  const id = String(formData.get("id") || "");
  removeHomework(id);
  revalidatePath("/");
  revalidatePath("/remember");
}

export async function saveAttempt(homeworkId: string, transcript: string) {
  const { getHomework } = await import("./store");
  const homework = getHomework(homeworkId);
  if (!homework) throw new Error("Homework not found");
  const scored = scoreReading(homework.passage, transcript);
  const attempt = {
    id: crypto.randomUUID(),
    at: new Date().toISOString(),
    transcript,
    ...scored,
  };
  addAttempt(homeworkId, attempt);
  revalidatePath("/");
  revalidatePath(`/h/${homeworkId}`);
  return attempt;
}

export async function rememberWords(homeworkId: string, words: string[]) {
  addRemember(homeworkId, words);
  revalidatePath("/remember");
}

export async function forgetWord(formData: FormData) {
  removeRemember(String(formData.get("id") || ""));
  revalidatePath("/remember");
}
