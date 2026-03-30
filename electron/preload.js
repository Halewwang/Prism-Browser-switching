import { contextBridge, ipcRenderer } from 'electron';

const validChannels = new Set([
  'get-installed-browsers',
  'installed-browsers',
  'open-in-browser',
  'open-in-browser-error',
  'close-window',
  'minimize-window',
  'maximize-window',
  'resize-me',
  'update-window-style',
  'view-mode-change',
  'deep-link',
]);

const validInvokeChannels = new Set([
  'get-app-version',
  'get-view-mode',
  'get-pending-deep-link',
  'select-source-app',
  'add-custom-browser',
  'start-download-update',
]);

contextBridge.exposeInMainWorld('prism', {
  send(channel, payload) {
    if (!validChannels.has(channel)) {
      throw new Error(`Blocked IPC send channel: ${channel}`);
    }
    ipcRenderer.send(channel, payload);
  },
  invoke(channel, payload) {
    if (!validInvokeChannels.has(channel)) {
      throw new Error(`Blocked IPC invoke channel: ${channel}`);
    }
    return ipcRenderer.invoke(channel, payload);
  },
  on(channel, listener) {
    if (!validChannels.has(channel)) {
      throw new Error(`Blocked IPC on channel: ${channel}`);
    }
    const wrapped = (_event, payload) => listener(payload);
    ipcRenderer.on(channel, wrapped);
    return () => ipcRenderer.removeListener(channel, wrapped);
  },
  removeAllListeners(channel) {
    if (!validChannels.has(channel)) {
      throw new Error(`Blocked IPC removeAllListeners channel: ${channel}`);
    }
    ipcRenderer.removeAllListeners(channel);
  },
});
