export interface PrismApi {
  send: (channel: string, payload?: unknown) => void;
  invoke: <T = unknown>(channel: string, payload?: unknown) => Promise<T>;
  on: <T = unknown>(channel: string, listener: (payload: T) => void) => () => void;
  removeAllListeners: (channel: string) => void;
}

export const getPrism = (): PrismApi | null => {
  if (typeof window === 'undefined') return null;
  return window.prism || null;
};
