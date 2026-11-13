export type Limit = { kind: string; percentUsed: number; resetsAt?: string }

export type Figures = {
  tokens?: number
  window: number
  percent?: number
  limits: Limit[]
}

declare module 'claude-code' {
  interface PluginState {
    stroka: { figures: Figures | null; effort: string | null }
  }
}
