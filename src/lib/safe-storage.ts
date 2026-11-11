/**
 * Acesso seguro ao localStorage. Em iframes, modo privado ou com cota cheia o
 * navegador pode bloquear o armazenamento: nesses casos o app segue funcionando em memória.
 */
const memory = new Map<string, string>();

export const safeStorage = {
  get(key: string): string | null {
    if (memory.has(key)) return memory.get(key) ?? null;
    try {
      return typeof window === 'undefined' ? null : window.localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key: string, value: string): void {
    try {
      window.localStorage.setItem(key, value);
      memory.delete(key);
    } catch {
      memory.set(key, value);
    }
  },
  remove(key: string): void {
    memory.delete(key);
    try {
      window.localStorage.removeItem(key);
    } catch {
      /* sem armazenamento disponível */
    }
  },
};

export function readJson<T>(key: string, fallback: T): T {
  const raw = safeStorage.get(key);
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export function writeJson(key: string, value: unknown): void {
  safeStorage.set(key, JSON.stringify(value));
}

export function newId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}
