import { useCallback, useEffect, useState } from 'react'
import { api, formatTs, type CollectResult, type Device } from '../api'

interface Props {
  inventory: string
  description: string
  onCollected: () => void
  onView: (device: string) => void
  onCompare: (devices: string[]) => void
}

type Status = { state: 'running' } | { state: 'done'; result: CollectResult }

export default function DevicesPanel({ inventory, description, onCollected, onView, onCompare }: Props) {
  const [devices, setDevices] = useState<Device[]>([])
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [status, setStatus] = useState<Record<string, Status>>({})
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [showCreds, setShowCreds] = useState(false)
  const [password, setPassword] = useState('')
  const [enablePassword, setEnablePassword] = useState('')

  const load = useCallback(() => {
    if (!inventory) return
    setLoading(true)
    setError(null)
    api
      .devices(inventory)
      .then((list) => {
        setDevices(list)
        setSelected((prev) => new Set(list.map((d) => d.name).filter((n) => prev.has(n))))
      })
      .catch((e: Error) => {
        setDevices([])
        setError(e.message)
      })
      .finally(() => setLoading(false))
  }, [inventory])

  useEffect(() => {
    setStatus({})
    load()
  }, [load])

  const collect = async (names: string[]) => {
    if (!names.length) return
    setStatus((s) => ({ ...s, ...Object.fromEntries(names.map((n) => [n, { state: 'running' } as Status])) }))
    try {
      const res = await api.collect({
        inventory,
        devices: names,
        password: password || undefined,
        enable_password: enablePassword || undefined,
      })
      setStatus((s) => ({
        ...s,
        ...Object.fromEntries(res.results.map((r) => [r.name, { state: 'done', result: r } as Status])),
      }))
      onCollected()
      load()
    } catch (e) {
      const msg = (e as Error).message
      setStatus((s) => ({
        ...s,
        ...Object.fromEntries(
          names.map((n) => [
            n,
            { state: 'done', result: { name: n, ok: false, error: msg, snapshot: null, lines: 0, seconds: 0 } } as Status,
          ]),
        ),
      }))
    }
  }

  const toggle = (name: string) =>
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(name)) next.delete(name)
      else next.add(name)
      return next
    })
  const allSelected = devices.length > 0 && selected.size === devices.length
  const selectedNames = devices.map((d) => d.name).filter((n) => selected.has(n))
  const running = Object.values(status).some((s) => s.state === 'running')
  const comparable = selectedNames.filter((n) => devices.find((d) => d.name === n)?.latest)

  return (
    <section className="panel">
      <div className="panel-head">
        <div>
          <h2>接続先デバイス</h2>
          {description && <p className="muted">{description}</p>}
        </div>
        <div className="actions">
          <button onClick={load} disabled={loading}>
            再読み込み
          </button>
          <button className="primary" disabled={!selectedNames.length || running} onClick={() => collect(selectedNames)}>
            選択したデバイスに接続して収集 ({selectedNames.length})
          </button>
          <button disabled={comparable.length < 2} onClick={() => onCompare(comparable)}>
            選択したデバイスを比較
          </button>
        </div>
      </div>

      <details className="creds" open={showCreds} onToggle={(e) => setShowCreds((e.target as HTMLDetailsElement).open)}>
        <summary>認証情報を入力して接続 (任意)</summary>
        <p className="muted">
          空欄の場合はインベントリと環境変数 (CBT_PASSWORD など) の値を使います。入力した値はこの収集リクエストにだけ使い、保存しません。
        </p>
        <div className="cred-fields">
          <label>
            パスワード
            <input type="password" autoComplete="off" value={password} onChange={(e) => setPassword(e.target.value)} />
          </label>
          <label>
            enable パスワード
            <input
              type="password"
              autoComplete="off"
              value={enablePassword}
              onChange={(e) => setEnablePassword(e.target.value)}
            />
          </label>
        </div>
      </details>

      {error && <div className="error">{error}</div>}

      <table className="grid devices">
        <thead>
          <tr>
            <th>
              <input
                type="checkbox"
                aria-label="すべて選択"
                checked={allSelected}
                onChange={() => setSelected(allSelected ? new Set() : new Set(devices.map((d) => d.name)))}
              />
            </th>
            <th>装置名</th>
            <th>機種 / SW</th>
            <th>接続</th>
            <th>認証</th>
            <th>最終収集</th>
            <th>状態</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {devices.map((d) => {
            const st = status[d.name]
            return (
              <tr key={d.name} className={selected.has(d.name) ? 'selected' : undefined}>
                <td>
                  <input
                    type="checkbox"
                    aria-label={`${d.name} を選択`}
                    checked={selected.has(d.name)}
                    onChange={() => toggle(d.name)}
                  />
                </td>
                <td className="mono strong">{d.name}</td>
                <td>
                  {d.model} <span className="muted">{d.sw}</span>
                  {!d.collector && <div className="warn">対応するコレクタなし</div>}
                </td>
                <td className="mono">
                  <span className={`badge ${d.protocol}`}>{d.protocol}</span> {d.host}:{d.port}
                </td>
                <td>{authLabel(d)}</td>
                <td>
                  {formatTs(d.latest)}
                  {d.snapshots > 1 && <span className="muted"> (全 {d.snapshots} 件)</span>}
                </td>
                <td>
                  <StatusCell status={st} />
                </td>
                <td className="row-actions">
                  <button disabled={st?.state === 'running'} onClick={() => collect([d.name])}>
                    接続して収集
                  </button>
                  <button disabled={!d.latest} onClick={() => onView(d.name)}>
                    表示
                  </button>
                </td>
              </tr>
            )
          })}
          {!devices.length && !loading && !error && (
            <tr>
              <td colSpan={8} className="muted center">
                デバイスがありません
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </section>
  )
}

function authLabel(d: Device): string {
  if (d.protocol === 'ssh') {
    const kind = d.auth === 'publickey' ? '公開鍵' : 'パスワード'
    return `${d.user ?? ''} / ${kind}${d.host_key_check && d.host_key_check !== 'yes' ? ` (host key: ${d.host_key_check})` : ''}`
  }
  return `${d.user ?? ''} / パスワード${d.has_password ? '' : ' (未設定)'}`
}

function StatusCell({ status }: { status?: Status }) {
  if (!status) return <span className="muted">—</span>
  if (status.state === 'running') return <span className="status running">接続中…</span>
  const r = status.result
  if (r.ok)
    return (
      <span className="status ok" title={`${r.seconds}s`}>
        OK ({r.lines} 行)
      </span>
    )
  return (
    <span className="status failed" title={r.error ?? ''}>
      FAILED: {r.error}
    </span>
  )
}
