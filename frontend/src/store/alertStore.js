import { create } from 'zustand'

const RING = 200   // max supervised-attack alerts in memory

export const useAlertStore = create((set) => ({
  alerts: [],
  push:  (a) => set((s) => ({ alerts: [a, ...s.alerts].slice(0, RING) })),
  clear: ()  => set({ alerts: [] }),
}))
