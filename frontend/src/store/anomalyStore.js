import { create } from 'zustand'

// AE flags ~75% of local-benign (domain-shift finding) — keep a larger window.
const RING = 500

export const useAnomalyStore = create((set) => ({
  anomalies: [],
  push:  (a) => set((s) => ({ anomalies: [a, ...s.anomalies].slice(0, RING) })),
  clear: ()  => set({ anomalies: [] }),
}))
