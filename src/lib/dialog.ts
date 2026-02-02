import { open } from "@tauri-apps/plugin-dialog";

export async function pickProjectFolder(): Promise<string | null> {
  const selected = await open({
    directory: true,
    multiple: false,
    title: "Open Project",
  });
  return selected;
}
