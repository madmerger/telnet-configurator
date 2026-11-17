import { Fragment, useEffect, useState } from 'react'
import {
  api,
  formatTs,
  type CompareResult,
  type DiffRow,
  type SectionDiff,
  type Snapshot,
  type StoredDevice,
} from '../api'

interface Props {
  initialDevices: string[]
  revision: number
}

interface Pick {
  device: string
  snapshot: string
}

const CONTEXT = 3
const GROUP_COLORS = ['#e8f5e9', '#fff3e0', '#e3f2fd', '#fce4ec', '#ede7f6', '#e0f7fa', '#f9fbe7']

export default function ComparePanel({ initialDevices, revision }: Props) {
  const [stored, setStored] = useState<StoredDevice[]>([])
  const [snapshots, setSnapshots] = useState<Record<string, Snapshot[]>>({})
  const [picks, setPicks] = useState<Pick[]>([])
  const [base, setBase] = useState(0)
  const [mask, setMask] = useState(true)
  const [onlyChanges, setOnlyChanges] = useState(true)
  const [result, setResult] = useState<CompareResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    api
      .storedDevices()
      .then((list) => {
        setStored(list)
        const names = list.map((s) => s.device)
        const initial = initialDevices.filter((d) => names.includes(d))
        const chosen = initial.length >= 2 ? initial : names.slice(0, 2)
        setPicks(chosen.map((device) => ({ device, snapshot: 'latest' })))
        setBase(0)
        setResult(null)
      })
      .catch((e: Error) => setError(e.message))
  }, [initialDevices, revision])

  useEffect(() => setResult(null), [picks, base, mask])

  useEffect(() => {
    for (const p of picks) {
      if (snapshots[p.device]) continue
      api.snapshots(p.device).then((s) => setSnapshots((cur) => ({ ...cur, [p.device]: s })))
    }
  }, [picks, snapshots])

  const update = (i: number, change: Partial<Pick>) =>
    setPicks((cur) => cur.map((p, j) => (j === i ? { ...p, ...change } : p)))
  const remove = (i: number) => {
    setPicks((cur) => cur.filter((_, j) => j !== i))
    setBase((b) => (i < b ? b - 1 : i === b ? 0 : b))
  }
  const add = () => {
    const used = new Set(picks.map((p) => p.device))
    const next = stored.find((s) => !used.has(s.device)) ?? stored[0]
    if (next) setPicks((cur) => [...cur, { device: next.device, snapshot: 'latest' }])
  }

  const run = async () => {
    setBusy(true)
    setError(null)
    try {
      setResult(await api.compare({ items: picks, base, mask_hostname: mask }))
    } catch (e) {
      setResult(null)
      setError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  if (stored.length < 2 && !error)
    return (
      <section className="panel">
        <p className="muted">比較には収集済みのコンフィグが 2 件以上必要です。</p>
      </section>
    )

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>コンフィグ比較</h2>
      </div>
      <table className="grid picks">
        <thead>
          <tr>
            <th>基準</th>
            <th>装置</th>
            <th>収集日時</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {picks.map((p, i) => (
            <tr key={i}>
              <td>
                <input
                  type="radio"
                  name="base"
                  aria-label={`${p.device} を基準にする`}
                  checked={base === i}
                  onChange={() => setBase(i)}
                />
              </td>
              <td>
                <select value={p.device} onChange={(e) => update(i, { device: e.target.value, snapshot: 'latest' })}>
                  {stored.map((s) => (
                    <option key={s.device} value={s.device}>
                      {s.device}
                    </option>
                  ))}
                </select>
              </td>
              <td>
                <select value={p.snapshot} onChange={(e) => update(i, { snapshot: e.target.value })}>
                  <option value="latest">最新</option>
                  {(snapshots[p.device] ?? []).map((s) => (
                    <option key={s.id} value={s.id}>
                      {formatTs(s.id)}
                    </option>
                  ))}
                </select>
              </td>
              <td>
                <button disabled={picks.length <= 2} onClick={() => remove(i)}>
                  削除
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="toolbar">
        <div className="actions">
          <button onClick={add}>比較対象を追加</button>
          <label className="check">
            <input type="checkbox" checked={mask} onChange={(e) => setMask(e.target.checked)} />
            ホスト名の違いを無視
          </label>
          <label className="check">
            <input type="checkbox" checked={onlyChanges} onChange={(e) => setOnlyChanges(e.target.checked)} />
            差分の周辺のみ表示
          </label>
        </div>
        <button className="primary" disabled={busy || picks.length < 2} onClick={run}>
          {busy ? '比較中…' : '比較する'}
        </button>
      </div>

      {error && <div className="error">{error}</div>}
      {result && <CompareView result={result} onlyChanges={onlyChanges} />}
    </section>
  )
}

function CompareView({ result, onlyChanges }: { result: CompareResult; onlyChanges: boolean }) {
  const label = (key: string) => {
    const it = result.items.find((i) => i.key === key)
    return it ? `${it.device} (${formatTs(it.snapshot)})` : key
  }
  return (
    <>
      <h3>サマリ</h3>
      <div className="scroll-x">
        <table className="grid matrix">
          <thead>
            <tr>
              <th>コマンド</th>
              {result.items.map((it) => (
                <th key={it.key}>
                  <div className="mono">{it.device}</div>
                  <div className="muted small">
                    {formatTs(it.snapshot)}
                    {it.key === result.base && ' · 基準'}
                  </div>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {result.commands.map((cmd) => {
              const row = result.matrix[cmd]
              const baseGroup = row[result.base]
              return (
                <tr key={cmd}>
                  <td className="mono">{cmd}</td>
                  {result.items.map((it) => {
                    const g = row[it.key]
                    if (g === null || g === undefined)
                      return (
                        <td key={it.key} className="cell missing">
                          なし
                        </td>
                      )
                    return (
                      <td key={it.key} className="cell" style={{ background: GROUP_COLORS[g % GROUP_COLORS.length] }}>
                        {it.key === result.base ? '基準' : g === baseGroup ? '同一' : `差分 (${String.fromCharCode(65 + g)})`}
                      </td>
                    )
                  })}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <p className="muted small">同じ色のセルは内容が完全に一致しています。</p>

      {result.diffs.map((d) => (
        <div key={d.key} className="target-diff">
          <h3>
            <span className="mono">{label(result.base)}</span> → <span className="mono">{label(d.key)}</span>{' '}
            {d.identical ? (
              <span className="status ok">差分なし</span>
            ) : (
              <span className="stat">
                <span className="add">+{d.added}</span> <span className="del">-{d.removed}</span>
              </span>
            )}
          </h3>
          {d.sections.map((s) => (
            <SectionView key={s.command} section={s} onlyChanges={onlyChanges} />
          ))}
        </div>
      ))}
    </>
  )
}

const STATUS_LABEL: Record<SectionDiff['status'], string> = {
  equal: '一致',
  changed: '差分あり',
  only_base: '基準のみ',
  only_target: '比較対象のみ',
}

function SectionView({ section, onlyChanges }: { section: SectionDiff; onlyChanges: boolean }) {
  const [open, setOpen] = useState(section.status !== 'equal')
  return (
    <details className={`section-diff ${section.status}`} open={open} onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)}>
      <summary>
        <span className="mono">{section.command}</span>
        <span className={`tag ${section.status}`}>{STATUS_LABEL[section.status]}</span>
        {section.status !== 'equal' && (
          <span className="stat">
            <span className="add">+{section.added}</span> <span className="del">-{section.removed}</span>
          </span>
        )}
      </summary>
      {open && <DiffTable rows={section.rows} onlyChanges={onlyChanges} />}
    </details>
  )
}

type Chunk = { kind: 'rows'; rows: DiffRow[] } | { kind: 'skip'; count: number }

function chunk(rows: DiffRow[], onlyChanges: boolean): Chunk[] {
  if (!onlyChanges) return [{ kind: 'rows', rows }]
  const keep = rows.map(() => false)
  rows.forEach((r, i) => {
    if (r.t === 'eq') return
    for (let k = Math.max(0, i - CONTEXT); k <= Math.min(rows.length - 1, i + CONTEXT); k++) keep[k] = true
  })
  const out: Chunk[] = []
  rows.forEach((r, i) => {
    const last = out[out.length - 1]
    if (keep[i]) {
      if (last?.kind === 'rows') last.rows.push(r)
      else out.push({ kind: 'rows', rows: [r] })
    } else if (last?.kind === 'skip') last.count++
    else out.push({ kind: 'skip', count: 1 })
  })
  return out
}

function DiffTable({ rows, onlyChanges }: { rows: DiffRow[]; onlyChanges: boolean }) {
  const chunks = chunk(rows, onlyChanges)
  return (
    <table className="code diff">
      <tbody>
        {chunks.map((c, ci) =>
          c.kind === 'skip' ? (
            <tr key={ci} className="skip">
              <td colSpan={4}>⋯ 一致する {c.count} 行を省略 ⋯</td>
            </tr>
          ) : (
            <Fragment key={ci}>
              {c.rows.map((r, ri) => (
                <tr key={ri} className={r.t}>
                  <td className="ln">{r.l ?? ''}</td>
                  <td className={`txt left ${r.lt === null ? 'empty' : ''}`}>{r.lt ?? ''}</td>
                  <td className="ln">{r.r ?? ''}</td>
                  <td className={`txt right ${r.rt === null ? 'empty' : ''}`}>{r.rt ?? ''}</td>
                </tr>
              ))}
            </Fragment>
          ),
        )}
      </tbody>
    </table>
  )
}
