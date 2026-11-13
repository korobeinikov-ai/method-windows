import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage, SessionRateLimit } from 'claude-code'

import type { Figures, Limit } from '../types'

// Та же строка, что stroka.py в терминале, только над полем ввода в приложении Claude:
// папка │ модель · глубина │ заполнение разговора │ лимит подписки.
// Все цифры даёт сам Claude Code, ничего не угадываем. В терминале не рисуем: там своя строка.

const figures = atom({ plugin: 'stroka', key: 'figures' } as const, null)
const effort = atom({ plugin: 'stroka', key: 'effort' } as const, null)

const tone = (v: number, yellow: number, red: number) =>
  v >= red ? 'error' : v >= yellow ? 'warning' : 'success'

const sizeLabel = (n: number) =>
  n % 1_000_000 === 0 ? `${n / 1_000_000}M` : `${Math.round(n / 1000)}k`

const two = (n: number) => String(n).padStart(2, '0')

// claude-opus-5-5[1m] → Opus 5.5; незнакомое имя — как есть
function modelName(id: string) {
  const m = /claude-([a-z]+)-(\d+)-(\d+)/i.exec(id)
  const family = m?.[1]
  if (!m || !family) return id
  return `${family.charAt(0).toUpperCase()}${family.slice(1)} ${m[2]}.${m[3]}`
}

// Когда лимит обнулится: в ближайшие сутки — время, дальше — дата
function resetLabel(iso: string, now: number) {
  const d = new Date(iso)
  return d.getTime() - now < 20 * 3600_000
    ? `${two(d.getHours())}:${two(d.getMinutes())}`
    : `${two(d.getDate())}.${two(d.getMonth() + 1)}`
}

function limitText(limits: Limit[], kind: string, name: string, now: number) {
  const w = limits.find(l => l.kind === kind)
  if (!w) return null
  const p = w.percentUsed
  const until = p >= 80 && w.resetsAt ? ` до ${resetLabel(w.resetsAt, now)}` : ''
  return { text: `${name} ${Math.floor(p)}%${until}`, color: tone(p, 50, 80) }
}

const pick = (context: SessionContextUsage, limits: readonly SessionRateLimit[]): Figures => ({
  tokens: context.tokens,
  window: context.window,
  percent: context.percent,
  limits: limits.map(({ kind, percentUsed, resetsAt }) => ({ kind, percentUsed, resetsAt })),
})

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const u = await $.session.usage()
    await update($, figures, () => pick(u.context, u.rateLimits))
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    await update($, figures, () => pick(e.context, e.rateLimits))
    return next(e)
  })

  // Глубину Claude Code сообщает только на ходу ответа; берём её у главного разговора, не у помощников
  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined) {
      const level = typeof e.effort === 'string' ? e.effort : null
      if (level !== (await read($, effort))) await update($, effort, () => level)
    }
    return yield* next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop' || e.props.hasSurvey) return next(e)

    const f = await read($, figures)
    const level = await read($, effort)
    const folder = (await $.session.root()).split('/').pop() ?? ''
    const model = modelName(await $.session.model())
    const now = await $.clock.now()
    const { Box, Text } = $.ui.resolve(e)

    const window = f?.window ?? 200_000
    const pct = f?.percent ?? 0
    const used = f?.tokens ?? Math.round((pct * window) / 100)
    // Жёлтый и красный — заранее: с 250k и 400k, в малом окне — с половины и трёх четвертей
    const fill = tone(used, Math.min(250_000, window / 2), Math.min(400_000, (window * 3) / 4))

    const limits = f?.limits ?? []
    const five = limitText(limits, 'five_hour', '5ч', now)
    const week = limitText(limits, 'seven_day', 'неделя', now)

    return (
      <Box flexDirection="row" flexWrap="wrap" gap={1}>
        <Text dimColor>{`📁 ${folder}`}</Text>
        <Text dimColor>│</Text>
        <Text>{`🧠 ${model}`}</Text>
        {level ? <Text dimColor>{`· ${level}`}</Text> : null}
        <Text dimColor>│</Text>
        <Text color={fill}>{`📊 разговор ${Math.floor(pct)}%`}</Text>
        <Text dimColor>{`(${Math.round(used / 1000)}k/${sizeLabel(window)})`}</Text>
        {five || week ? <Text dimColor>│</Text> : null}
        {five || week ? <Text>⏳ лимит</Text> : null}
        {five ? <Text color={five.color}>{five.text}</Text> : null}
        {five && week ? <Text dimColor>·</Text> : null}
        {week ? <Text color={week.color}>{week.text}</Text> : null}
      </Box>
    )
  })
}
