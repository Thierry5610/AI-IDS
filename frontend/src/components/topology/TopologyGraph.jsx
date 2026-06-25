/**
 * TopologyGraph — react-force-graph-2d wrapper, custom-painted to the VIGIL look.
 *
 * Nodes: circular typed badges (glyph by inferred host type) + IP label; internal
 * hosts get an accent ring, external a muted ring; selected highlights lime.
 * Links: gently curved hairlines carrying a soft GLOW PULSE flowing src→dst.
 *
 * NOTE: the glowing pulse + (page) galaxy backdrop are intentional, user-approved
 * deviations from the otherwise-flat design system. Keep
 * them subtle — do not "flatten" them back.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import ForceGraph2D from 'react-force-graph-2d'
import { HOST_TYPES, GLYPHS } from '../../constants/hosts'
import './TopologyGraph.css'

const CURVATURE = 0.25

// Resolve theme tokens once (canvas can't read CSS var()).
function useThemeColors() {
  return useMemo(() => {
    const cs = getComputedStyle(document.documentElement)
    const g = v => cs.getPropertyValue(v).trim() || '#888'
    return {
      lime: g('--lime'), cyan: g('--cyan'), violet: g('--violet'),
      green: g('--green'), amber: g('--amber'), red: g('--red'),
      muted: g('--muted'), border: g('--border-strong'),
      surface: g('--surface-2'), text: g('--text'),
    }
  }, [])
}

// Stable per-link phase offset so pulses don't all fire in lockstep.
function hashSeed(s) {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return (Math.abs(h) % 1000) / 1000
}

const glyphCache = {}
function glyphPath(key) {
  const d = GLYPHS[key]
  if (!d) return null
  if (!glyphCache[d]) glyphCache[d] = new Path2D(d)
  return glyphCache[d]
}

function quadPoint(s, c, t, u) {
  const m = 1 - u
  return {
    x: m * m * s.x + 2 * m * u * c.x + u * u * t.x,
    y: m * m * s.y + 2 * m * u * c.y + u * u * t.y,
  }
}

const nodeRadius = n => 9 + Math.min(Math.sqrt(n.count || 1) * 2, 13)

export default function TopologyGraph({ graph, mode, selectedId, onSelect }) {
  const wrapRef = useRef(null)
  const fgRef = useRef(null)
  const cacheRef = useRef(new Map())          // id → node obj (preserve positions)
  const [size, setSize] = useState({ w: 600, h: 540 })
  const colors = useThemeColors()

  // Container sizing
  useEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const ro = new ResizeObserver(() => {
      const r = el.getBoundingClientRect()
      setSize({ w: Math.max(r.width, 10), h: Math.max(r.height, 10) })
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  // Reconcile to stable node refs so live updates don't reset the layout.
  const data = useMemo(() => {
    const cache = cacheRef.current
    const keep = new Set()
    const nodes = graph.nodes.map(n => {
      keep.add(n.id)
      const ex = cache.get(n.id)
      if (ex) { Object.assign(ex, n); return ex }   // keeps x/y/vx/vy
      cache.set(n.id, n); return n
    })
    for (const id of [...cache.keys()]) if (!keep.has(id)) cache.delete(id)
    const links = graph.links.map(l => ({
      source: l.source, target: l.target, count: l.count, sev: l.sev,
      seed: hashSeed(`${l.source}>${l.target}`),
    }))
    return { nodes, links }
  }, [graph])

  // Force layout: stronger local repulsion to declutter, capped range so disconnected
  // components don't drift apart; comfortable link distance for connected pairs.
  useEffect(() => {
    const fg = fgRef.current
    if (!fg) return
    fg.d3Force('charge').strength(-180).distanceMax(220)
    fg.d3Force('link').distance(60)
    fg.d3ReheatSimulation()
  }, [data])

  const sevColor = sev =>
    ({ critical: colors.red, high: colors.amber, medium: colors.cyan, low: colors.muted }[sev] || colors.muted)
  const linkAccent = link =>
    mode === 'anomalies' ? colors.violet : sevColor(link.sev)

  function paintNode(node, ctx, scale) {
    const meta = HOST_TYPES[node.type] || HOST_TYPES.host
    const accent = mode === 'anomalies' ? colors.violet : (colors[meta.colorKey] || colors.muted)
    const R = nodeRadius(node)
    const isSel = node.id === selectedId

    ctx.beginPath()
    ctx.arc(node.x, node.y, R, 0, 2 * Math.PI)
    ctx.fillStyle = colors.surface
    ctx.fill()
    ctx.lineWidth = (isSel ? 2 : node.internal ? 1.6 : 1) / scale
    ctx.strokeStyle = isSel ? colors.lime : (node.internal ? accent : colors.border)
    ctx.stroke()

    // typed glyph
    const p = glyphPath(meta.glyph)
    if (p) {
      ctx.save()
      ctx.translate(node.x, node.y)
      const s = (R * 1.15) / 24
      ctx.scale(s, s)
      ctx.translate(-12, -12)
      ctx.lineWidth = 1.8 / s
      ctx.lineJoin = 'round'; ctx.lineCap = 'round'
      ctx.strokeStyle = accent
      ctx.stroke(p)
      ctx.restore()
    }

    // IP label (constant pixel size)
    if (scale > 0.55) {
      ctx.font = `${10 / scale}px var(--f-mono), monospace`
      ctx.textAlign = 'center'; ctx.textBaseline = 'top'
      ctx.fillStyle = isSel ? colors.text : colors.muted
      ctx.fillText(node.id, node.x, node.y + R + 3 / scale)
    }
  }

  function paintLink(link, ctx, scale) {
    const s = link.source, t = link.target
    if (!s || !t || s.x == null || t.x == null) return
    const mx = (s.x + t.x) / 2, my = (s.y + t.y) / 2
    const dx = t.x - s.x, dy = t.y - s.y
    const cx = mx - dy * CURVATURE, cy = my + dx * CURVATURE
    const col = linkAccent(link)

    // base hairline
    ctx.beginPath()
    ctx.moveTo(s.x, s.y)
    ctx.quadraticCurveTo(cx, cy, t.x, t.y)
    ctx.strokeStyle = colors.border
    ctx.lineWidth = 0.7 / scale
    ctx.stroke()

    // soft glow pulse travelling src→dst
    const u = ((performance.now() / 1500) + link.seed) % 1
    const pos = quadPoint(s, { x: cx, y: cy }, t, u)
    ctx.save()
    ctx.shadowBlur = 16 / scale
    ctx.shadowColor = col
    ctx.fillStyle = col
    ctx.beginPath()
    ctx.arc(pos.x, pos.y, 2.4 / scale, 0, 2 * Math.PI)
    ctx.fill()
    ctx.shadowBlur = 0
    ctx.fillStyle = colors.text
    ctx.beginPath()
    ctx.arc(pos.x, pos.y, 0.9 / scale, 0, 2 * Math.PI)
    ctx.fill()
    ctx.restore()
  }

  return (
    <div ref={wrapRef} className="topo-graph">
      <ForceGraph2D
        ref={fgRef}
        width={size.w}
        height={size.h}
        graphData={data}
        backgroundColor="rgba(0,0,0,0)"
        nodeCanvasObject={paintNode}
        nodePointerAreaPaint={(node, color, ctx) => {
          ctx.fillStyle = color
          ctx.beginPath()
          ctx.arc(node.x, node.y, nodeRadius(node) + 2, 0, 2 * Math.PI)
          ctx.fill()
        }}
        nodeLabel={n => n.id}
        linkCanvasObject={paintLink}
        linkCurvature={CURVATURE}
        /* invisible particles keep the render loop alive so the pulse animates */
        linkDirectionalParticles={1}
        linkDirectionalParticleWidth={0.01}
        linkDirectionalParticleColor={() => 'rgba(0,0,0,0)'}
        cooldownTime={4000}
        onNodeClick={n => onSelect(n)}
        onBackgroundClick={() => onSelect(null)}
      />
    </div>
  )
}
