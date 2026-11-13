import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'stroka',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

test('в приложении строка как в терминале, в самом терминале её нет', async ($, on) => {
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { tokens: 91_000, window: 1_000_000, percent: 9 },
      rateLimits: [
        { kind: 'five_hour', percentUsed: 4 },
        { kind: 'seven_day', percentUsed: 27 },
      ],
    },
  }))
  on('session.root', () => ({ value: '/home/x/vibecoding/kofeynya-zerno' }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('clock.now', () => ({ value: 0 }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const app = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect((await app.find({ type: 'Text', text: /kofeynya-zerno/ }))?.text).toBe('📁 kofeynya-zerno')
  expect((await app.find({ type: 'Text', text: /Opus/ }))?.text).toBe('🧠 Opus 5.5')
  expect((await app.find({ type: 'Text', text: /разговор/ }))?.text).toBe('📊 разговор 9%')
  expect((await app.find({ type: 'Text', text: /k\// }))?.text).toBe('(91k/1M)')
  expect((await app.find({ type: 'Text', text: /5ч/ }))?.text).toBe('5ч 4%')
  expect((await app.find({ type: 'Text', text: /неделя/ }))?.text).toBe('неделя 27%')
  await app.unmount()

  const term = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await term.find({ type: 'Text', text: /разговор/ })).toBeUndefined()
  await term.unmount()
})
